// Copyright (c) 2025 Alexander5015
// This file is licensed under the BSD 3-Clause License.

#import <Foundation/Foundation.h>
#include <signal.h>

#import "MediaRemoteAdapter.h"
#import "adapter/get.h"
#import "test/NowPlayingTest.h"
#import "utility/helpers.h"

static NSTask *nowPlayingClientHelperTask = nil;
static NSFileHandle *helperInput = nil;
static NSFileHandle *helperOutput = nil;

void cleanup_helper() {
    if (nowPlayingClientHelperTask && helperInput && helperOutput) {
        @try {
            [helperInput writeData:[@"cleanup\n"
                                       dataUsingEncoding:NSUTF8StringEncoding]];
            [helperInput closeFile];
            [helperOutput availableData];
            [helperOutput closeFile];
            [nowPlayingClientHelperTask waitUntilExit];
        } @catch (__unused NSException *exception) {
        }
    } else if (nowPlayingClientHelperTask) {
        @try {
            [nowPlayingClientHelperTask terminate];
            [nowPlayingClientHelperTask waitUntilExit];
        } @catch (__unused NSException *exception) {
        }
    }
}

void cleanup_and_exit() {
    cleanup_helper();
    exit(1);
}

void handleSignal(int signal) {
    if (signal == SIGINT || signal == SIGTERM)
        cleanup_and_exit();
}

extern void adapter_test(void) {
    @autoreleasepool {
        signal(SIGINT, handleSignal);
        signal(SIGTERM, handleSignal);

        // If adapterOutput is not null, we know the adapter is working
        // correctly
        NSDictionary *result = internal_get(YES);
        if (result != nil) {
            cleanup_helper();
            exit(0);
        }

        // Instantiate helper to ensure MediaRemote has data
        // We only do this if adapterOutput is null to minimize the impact on
        // other apps using the adapter
        NSString *helperPath =
            NSProcessInfo.processInfo
                .environment[@"MEDIAREMOTEADAPTER_TEST_CLIENT_PATH"];
        if (helperPath.length == 0) {
            printErrf(@"Test client path is missing");
            cleanup_helper();
            exit(1);
        }

        // Set up pipes for communication with the helper process
        NSPipe *inputPipe = [NSPipe pipe];
        NSPipe *outputPipe = [NSPipe pipe];

        nowPlayingClientHelperTask = [[NSTask alloc] init];
        nowPlayingClientHelperTask.launchPath = helperPath;
        nowPlayingClientHelperTask.standardInput = inputPipe;
        nowPlayingClientHelperTask.standardOutput = outputPipe;

        @try {
            [nowPlayingClientHelperTask launch];
        } @catch (NSException *exception) {
            printErrf(
                @"Exeption while trying to launch test client task: %@: %@",
                exception.name, exception.reason);
            cleanup_helper();
            exit(1);
        }

        helperInput = inputPipe.fileHandleForWriting;
        helperOutput = outputPipe.fileHandleForReading;

        // Wait for setup signal from helper
        NSData *setupData = [helperOutput availableData];
        NSString *setupMsg =
            [[NSString alloc] initWithData:setupData
                                  encoding:NSUTF8StringEncoding];
        if (![setupMsg containsString:@"setup_done"]) {
            printErrf(@"The test client did not signal setup_done");
            cleanup_helper();
            exit(1);
        }

        // Small delay to ensure new data is available, for some reason the
        // first call to adapter_get slows down MediaRemote?
        [NSThread sleepForTimeInterval:0.01];

        result = internal_get(YES);
        if (result != nil) {
            cleanup_helper();
            exit(0);
        }

        cleanup_helper();
        exit(1);
    }
}
