// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#import <Foundation/Foundation.h>

#import "adapter/globals.h"
#import "utility/helpers.h"
#import "utility/NowPlayingTestClient/NowPlayingTest.h"

extern void adapter_get(void);

extern void _adapter_is_it_broken_yet() {
    setenv("ADAPTER_TEST_MODE", "1", 1);

    NSString *helperPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"NOWPLAYING_CLIENT"];
    if (!helperPath || [helperPath length] == 0) {
        unsetenv("ADAPTER_TEST_MODE");
        printOut(@"1");
        exit(1);
    }

    NSPipe *toHelper = [NSPipe pipe];
    NSPipe *fromHelper = [NSPipe pipe];

    NSTask *task = [[NSTask alloc] init];
    @try {
        [task setLaunchPath:helperPath];
        [task setStandardInput:toHelper];
        [task setStandardOutput:fromHelper];
        [task launch];
    } @catch (NSException *exception) {
        unsetenv("ADAPTER_TEST_MODE");
        printOut(@"1");
        exit(1);
    }

    NSFileHandle *writeToHelper = [toHelper fileHandleForWriting];
    NSFileHandle *readFromHelper = [fromHelper fileHandleForReading];

    NSData *setupData = [readFromHelper availableData];
    NSString *setupMsg = [[NSString alloc] initWithData:setupData encoding:NSUTF8StringEncoding];
    if (![setupMsg containsString:@"setup_done"]) {
        printErrf(@"NowPlayingTestClient did not signal setup_done");
        [task terminate];
        unsetenv("ADAPTER_TEST_MODE");
        printOut(@"1");
        exit(1);
    }

    NSPipe *pipe = [NSPipe pipe];
    NSFileHandle *readHandle = [pipe fileHandleForReading];
    int originalStdout = dup(STDOUT_FILENO);
    dup2([[pipe fileHandleForWriting] fileDescriptor], STDOUT_FILENO);

    adapter_get();

    fflush(stdout);
    dup2(originalStdout, STDOUT_FILENO);
    close(originalStdout);

    [[pipe fileHandleForWriting] closeFile];

    NSData *data = [readHandle readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    unsetenv("ADAPTER_TEST_MODE");

    NSString *cleanupMsg = @"cleanup\n";
    [writeToHelper writeData:[cleanupMsg dataUsingEncoding:NSUTF8StringEncoding]];
    [writeToHelper closeFile];

    [readFromHelper availableData];
    [readFromHelper closeFile];

    [task waitUntilExit];

    if ([output isEqualToString:@"null"]) {
        printOut(@"1");
        exit(0);
    } else {
        printOut(@"0");
        exit(1);
    }
}
