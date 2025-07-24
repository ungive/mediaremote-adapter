// Copyright (c) 2025 Alexander5015
// This file is licensed under the BSD 3-Clause License.

#import <Foundation/Foundation.h>
#import "MediaRemoteAdapter.h"
#import "utility/helpers.h"
#import "utility/NowPlayingTestClient/NowPlayingTest.h"
#include <signal.h>

static NSTask *nowPlayingClientHelperTask = nil;

void cleanup_and_exit() {
    unsetenv("ADAPTER_TEST_MODE");
    if (nowPlayingClientHelperTask) {
        @try {
            [nowPlayingClientHelperTask terminate];
            [nowPlayingClientHelperTask waitUntilExit];
        } @catch (__unused NSException *exception) {}
    }
    exit(1);
}

void handleSignal(int signal) {
    if(signal == SIGINT || signal == SIGTERM) cleanup_and_exit();
}

extern void _adapter_is_it_broken_yet(void) {
    @autoreleasepool {
        signal(SIGINT, handleSignal);
        signal(SIGTERM, handleSignal);

        setenv("ADAPTER_TEST_MODE", "1", 1);

        NSPipe *stdoutPipe = [NSPipe pipe];
        int originalStdout = dup(STDOUT_FILENO);
        dup2(stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO);

        adapter_get();

        fflush(stdout);
        dup2(originalStdout, STDOUT_FILENO);
        close(originalStdout);
        [stdoutPipe.fileHandleForWriting closeFile];

        NSData *adapterData = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
        NSString *adapterOutput = [[NSString alloc] initWithData:adapterData encoding:NSUTF8StringEncoding];
        adapterOutput = [adapterOutput stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

        // If adapterOutput is not null, we know the adapter is working correctly
        if (![adapterOutput isEqualToString:@"null"]) {
            unsetenv("ADAPTER_TEST_MODE");
            printOut(@"0");
            exit(0);
        }

        // Instantiate helper to ensure MediaRemote has data
        // We only do this if adapterOutput is null to minimize the impact on other apps using the adapter
        NSString *helperPath = NSProcessInfo.processInfo.environment[@"NOWPLAYING_CLIENT"];
        if (helperPath.length == 0) {
            unsetenv("ADAPTER_TEST_MODE");
            printErrf(@"NowPlayingTestClient helper path is not set");
            printOut(@"1");
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
        } @catch (__unused NSException *exception) {
            unsetenv("ADAPTER_TEST_MODE");
            printErrf(@"Exeption while trying to launch NowPlayingClient Task");
            printOut(@"1");
            exit(1);
        }

        NSFileHandle *helperInput = inputPipe.fileHandleForWriting;
        NSFileHandle *helperOutput = outputPipe.fileHandleForReading;

        // Wait for setup signal from helper
        NSData *setupData = [helperOutput availableData];
        NSString *setupMsg = [[NSString alloc] initWithData:setupData encoding:NSUTF8StringEncoding];
        if (![setupMsg containsString:@"setup_done"]) {
            printErrf(@"NowPlayingTestClient did not signal setup_done");
            [nowPlayingClientHelperTask terminate];
            unsetenv("ADAPTER_TEST_MODE");
            printOut(@"1");
            exit(1);
        }


        // Repeat adapter_get with helper running
        NSPipe *stdoutPipe2 = [NSPipe pipe];
        int originalStdout2 = dup(STDOUT_FILENO);
        dup2(stdoutPipe2.fileHandleForWriting.fileDescriptor, STDOUT_FILENO);

        // Small delay to ensure new data is available, for some reason the first call to adapter_get slows down MediaRemote?
        [NSThread sleepForTimeInterval:0.01];

        adapter_get();

        fflush(stdout);
        dup2(originalStdout2, STDOUT_FILENO);
        close(originalStdout2);
        [stdoutPipe2.fileHandleForWriting closeFile];

        NSData *adapterData2 = [stdoutPipe2.fileHandleForReading readDataToEndOfFile];
        NSString *adapterOutput2 = [[NSString alloc] initWithData:adapterData2 encoding:NSUTF8StringEncoding];
        adapterOutput2 = [adapterOutput2 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

        unsetenv("ADAPTER_TEST_MODE");

        // Cleanup helper
        [helperInput writeData:[@"cleanup\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [helperInput closeFile];
        [helperOutput availableData];
        [helperOutput closeFile];
        [nowPlayingClientHelperTask waitUntilExit];

        BOOL isBroken = [adapterOutput2 isEqualToString:@"null"];
        printOut(isBroken ? @"1" : @"0");
        exit(isBroken ? 1 : 0);
    }
}
