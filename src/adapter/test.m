// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#include <errno.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <sys/user.h>

#import <Foundation/Foundation.h>

#import "adapter/globals.h"
#import "utility/helpers.h"

static int findProcessId(NSString *processName) {
    size_t size;
    if (sysctlbyname("kern.proc.all", NULL, &size, NULL, 0) == -1) {
        printErrf(@"Getting kern.proc.all size failed: %d", errno);
        return 0;
    }
    struct kinfo_proc *processList = malloc(size);
    if (!processList) {
        perror("malloc error");
        return 0;
    }
    if (sysctlbyname("kern.proc.all", processList, &size, NULL, 0) == -1) {
        printErrf(@"Getting kern.proc.all failed: %d", errno);
        free(processList);
        return 0;
    }
    int processCount = size / sizeof(struct kinfo_proc);
    for (int i = 0; i < processCount; i++) {
        struct kinfo_proc process = processList[i];
        if (strcmp(process.kp_proc.p_comm, [processName UTF8String]) == 0) {
            pid_t pid = process.kp_proc.p_pid;
            free(processList);
            return pid;
        }
    }
    free(processList);
    return 0;
}

static NSString *getCommandOutput(NSString *command, NSArray *arguments) {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:command];
    [task setArguments:arguments];
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    // [task setStandardError:pipe];
    [task launch];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data
                                             encoding:NSUTF8StringEncoding];
    return output;
}

static NSString *getRegexMatch(NSString *pattern, NSString *text, int index) {
    NSError *error = nil;
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:pattern
                                                  options:0
                                                    error:&error];
    if (error) {
        printErrf(@"Failed to create regex %@: %@", pattern, error);
        exit(1);
        return nil;
    }
    NSTextCheckingResult *match =
        [regex firstMatchInString:text
                          options:0
                            range:NSMakeRange(0, text.length)];
    if (!match) {
        return nil;
    }
    NSRange matchRange = [match rangeAtIndex:index];
    NSString *matchString = [text substringWithRange:matchRange];
    return matchString;
}

static NSString *getFirstRegexMatch(NSString *pattern, NSString *text) {
    return getRegexMatch(pattern, text, 1);
}

static NSNumber *stringToNumber(NSString *text) {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    NSNumber *number = [formatter numberFromString:text];
    [formatter release];
    return number;
}

// Checks whether the current process is entitled for using the MediaRemote
// framework. The following served as reference for these checks:
// https://github.com/aviwad/LyricFever/issues/94#issuecomment-2746155419
static bool isProcessEntitledForMediaRemote(NSString *bundleIdentifier,
                                            NSNumber *entitlements) {
    if (entitlements) {
        if ([entitlements integerValue] == 0) {
            return false;
        }
        if ([entitlements integerValue] == 512) {
            return true;
        }
    }
    if (bundleIdentifier) {
        if ([bundleIdentifier hasPrefix:@"com.apple."]) {
            return true;
        }
    }
    return false;
}

// FIXME This does not appear to work on all platforms, needs debugging.
extern void _adapter_test() {
    // Get the current process's PID.
    __block const int pid = [[NSProcessInfo processInfo] processIdentifier];
    if (pid <= 0) {
        printErrf(@"The current process does not have a valid PID: %d", pid);
        exit(1);
        return;
    }

    // Find the PID of the MediaRemote daemon (mediaremoted).
    __block const int pidMediaremoted = findProcessId(@"mediaremoted");
    if (pid <= 0) {
        printErr(@"Could not find mediaremoted process");
        exit(1);
        return;
    }

    // Stop the time so we can reduce the number of log items
    // by filtering by entry age.
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();

    // Trigger logs of mediaremoted by using the MediaRemote API.
    id semaphore = dispatch_semaphore_create(0);
    g_mediaRemote.getNowPlayingInfo(g_dispatchQueue,
                                    ^(NSDictionary *information) {
                                      dispatch_semaphore_signal(semaphore);
                                    });
    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC);
    long result = dispatch_semaphore_wait(semaphore, timeout);
    if (result != 0) {
        printErr(@"Response from MRMediaRemoteGetNowPlayingInfo timed out");
        exit(1);
    }
    dispatch_release(semaphore);

    // Compute the amount of time that elapsed.
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    NSInteger elapsedTime = (NSInteger)ceil(endTime - startTime);
    NSInteger elapsedTimeWithExtra = elapsedTime + 5;

    // Read the recent log history of the mediaremoted process.
    // We cannot use "log stream" because it doesn't output anything sometimes
    // (who knows why).
    NSString *output = getCommandOutput(@"/usr/bin/log", @[
        @"show",
        @"--predicate",
        [NSString stringWithFormat:@"processIdentifier == %d and "
                                   @"eventMessage contains 'entitlements'",
                                   pidMediaremoted],
        @"--last",
        [NSString stringWithFormat:@"%ld", elapsedTimeWithExtra],
        @"--style",
        @"ndjson",
    ]);

    // Parse the output data and filter by entitlement messages
    // for the current process.
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSString *trimmedLine =
            [line stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmedLine.length == 0) {
            continue;
        }
        NSData *data = [trimmedLine dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        NSDictionary *jsonDict =
            [NSJSONSerialization JSONObjectWithData:data
                                            options:0
                                              error:&error];
        if (error) {
            printErrf(@"Error parsing JSON: %@", error.localizedDescription);
            continue;
        }
        if (jsonDict[@"finished"] &&
            [jsonDict[@"finished"] isEqualToNumber:@(1)]) {
            break;
        }
        if (!jsonDict[@"eventMessage"]) {
            continue;
        }

        NSString *requestingPid = getFirstRegexMatch(
            @"<[^>]*MediaRemote[^>]+pid\\s*=\\s*([\\d]+)[^>]*>", line);
        if (![requestingPid
                isEqualToString:[NSString stringWithFormat:@"%d", pid]]) {
            continue;
        }

        NSString *bundleIdentifier =
            getFirstRegexMatch(@"<[^>]*MediaRemote[^>]+bundleIdentifier"
                               @"\\s*=\\s*([a-zA-Z\\.]+)[^>]*>",
                               line);
        NSString *entitlementsText = getFirstRegexMatch(
            @"<[^>]*MediaRemote[^>]+entitlements\\s*=\\s*([\\d]+)[^>]*>", line);
        NSNumber *entitlements = stringToNumber(entitlementsText);

        if (isProcessEntitledForMediaRemote(bundleIdentifier, entitlements)) {
            // Print 1 when the process is entitled.
            printOut(@"1");
            exit(0);
            return;
        }
    }

    // Print 0 when the process is not entitled.
    printOut(@"0");
    exit(0);
}
