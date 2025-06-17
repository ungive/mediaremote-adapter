// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#include <stdio.h>

#import "helpers.h"

void printOut(NSString *message) {
    fprintf(stdout, "%s\n", [message UTF8String]);
    fflush(stdout);
}

void printErr(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    fflush(stderr);
}

void printErrf(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *formattedMessage = [[NSString alloc] initWithFormat:format
                                                        arguments:args];
    va_end(args);
    fprintf(stderr, "%s\n", [formattedMessage UTF8String]);
    fflush(stderr);
}

void fail(NSString *message) {
    printErr(message);
    exit(1);
}

NSString *formatError(NSError *error) {
    return
        [NSString stringWithFormat:@"%@ (%@:%ld)", [error localizedDescription],
                                   [error domain], (long)[error code]];
}

NSString *serializeJsonSafe(id any) {
    NSError *error;
    NSData *serialized = [NSJSONSerialization dataWithJSONObject:any
                                                         options:0
                                                           error:&error];
    if (!serialized) {
        return nil;
    }
    return [[NSString alloc] initWithData:serialized
                                 encoding:NSUTF8StringEncoding];
}

bool appForPID(int pid, void (^block)(NSRunningApplication *)) {
    if (pid <= 0) {
        return false;
    }
    NSRunningApplication *process =
        [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (process == nil) {
        printErr(
            [NSString stringWithFormat:@"Failed to determine bundle identifier "
                                       @"for process with PID %d",
                                       pid]);
        return false;
    }
    if (process.bundleIdentifier == nil) {
        printErr([NSString
            stringWithFormat:
                @"The bundle identifier for process with PID %d is nil", pid]);
        return false;
    }
    block(process);
    return true;
}
