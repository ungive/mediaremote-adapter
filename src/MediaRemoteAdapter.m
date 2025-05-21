#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/sysctl.h>
#include <unistd.h>

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#import "Debounce.h"
#import "MediaRemote.h"
#import "MediaRemoteAdapter.h"

static const double INDEFINITELY = 1e10;
static const double DEBOUNCE_DELAY = 0.1; // seconds

// These keys identify a now playing item uniquely.
static NSArray<NSString *> *identifyingItemKeys(void) {
    return @[ kBundleIdentifier, kTitle, kArtist, kAlbum ];
}

static MediaRemote *_mediaRemote = NULL;
static CFRunLoopRef _runLoop = NULL;
static dispatch_queue_t _queue;

static void printOut(NSString *message) {
    fprintf(stdout, "%s\n", [message UTF8String]);
    fflush(stdout);
}

static void printErr(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    fflush(stderr);
}

static void printErrf(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *formattedMessage = [[NSString alloc] initWithFormat:format
                                                        arguments:args];
    va_end(args);
    fprintf(stderr, "%s\n", [formattedMessage UTF8String]);
    fflush(stderr);
}

static NSString *serializeJsonSafe(id any) {
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

static NSString *formatError(NSError *error) {
    return
        [NSString stringWithFormat:@"%@ (%@:%ld)", [error localizedDescription],
                                   [error domain], (long)[error code]];
}

static NSString *serializeData(NSDictionary *data, BOOL diff) {
    NSError *error;
    NSDictionary *wrappedData = @{
        @"type" : @"data",
        @"diff" : @(diff),
        @"payload" : data,
    };
    NSData *serialized = [NSJSONSerialization dataWithJSONObject:wrappedData
                                                         options:0
                                                           error:&error];
    if (!serialized) {
        printErr([NSString stringWithFormat:@"Failed for serialize data: %@",
                                            formatError(error)]);
        return nil;
    }
    return [[NSString alloc] initWithData:serialized
                                 encoding:NSUTF8StringEncoding];
}

static NSMutableDictionary *
convertNowPlayingInformation(NSDictionary *information) {
    NSMutableDictionary *data = [NSMutableDictionary dictionary];

    void (^setKey)(id, id) = ^(id key, id fromKey) {
      id value = [NSNull null];
      if (information != nil) {
          id result = information[fromKey];
          if (result != nil) {
              value = result;
          }
      }
      [data setObject:value forKey:key];
    };

    void (^setValue)(id key, id (^)(void)) = ^(id key, id (^evaluate)(void)) {
      id value = nil;
      if (information != nil) {
          value = evaluate();
      }
      if (value != nil) {
          [data setObject:value forKey:key];
      } else {
          [data setObject:[NSNull null] forKey:key];
      }
    };

    setKey(kTitle, kMRMediaRemoteNowPlayingInfoTitle);
    setKey(kArtist, kMRMediaRemoteNowPlayingInfoArtist);
    setKey(kAlbum, kMRMediaRemoteNowPlayingInfoAlbum);
    setValue(kDurationMicros, ^id {
      id duration = information[kMRMediaRemoteNowPlayingInfoDuration];
      if (duration != nil) {
          NSTimeInterval durationMicros = [duration doubleValue] * 1000 * 1000;
          return @(floor(durationMicros));
      }
      return nil;
    });
    setValue(kElapsedTimeMicros, ^id {
      id elapsedTime = information[kMRMediaRemoteNowPlayingInfoElapsedTime];
      if (elapsedTime != nil) {
          NSTimeInterval elapsedTimeMicros =
              [elapsedTime doubleValue] * 1000 * 1000;
          return @(floor(elapsedTimeMicros));
      }
      return nil;
    });
    setValue(kTimestampEpochMicros, ^id {
      NSDate *timestamp = information[kMRMediaRemoteNowPlayingInfoTimestamp];
      if (timestamp != nil) {
          NSTimeInterval timestampEpoch = [timestamp timeIntervalSince1970];
          NSTimeInterval timestampEpochMicro = timestampEpoch * 1000 * 1000;
          return @(floor(timestampEpochMicro));
      }
      return nil;
    });
    setKey(kArtworkMimeType, kMRMediaRemoteNowPlayingInfoArtworkMIMEType);
    setValue(kArtworkDataBase64, ^id {
      NSData *artworkData =
          information[kMRMediaRemoteNowPlayingInfoArtworkData];
      if (artworkData != nil) {
          return [artworkData base64EncodedStringWithOptions:0];
      }
      return nil;
    });

    return data;
}

static NSDictionary *createDiff(NSDictionary *a, NSDictionary *b) {
    NSMutableDictionary *diff = [NSMutableDictionary dictionary];
    NSMutableSet *allKeys = [NSMutableSet setWithArray:a.allKeys];
    [allKeys addObjectsFromArray:b.allKeys];
    for (id key in allKeys) {
        id oldValue = a[key];
        id newValue = b[key];
        BOOL valuesDiffer = NO;
        if (oldValue == nil && newValue != nil) {
            valuesDiffer = YES;
        } else if (oldValue != nil && newValue == nil) {
            valuesDiffer = YES;
        } else if (![oldValue isEqual:newValue]) {
            valuesDiffer = YES;
        }
        if (valuesDiffer) {
            diff[key] = newValue ?: [NSNull null];
        }
    }
    return [diff copy];
}

static NSDictionary *previousData = nil;

static bool isSameItemIdentity(NSDictionary *a, NSDictionary *b) {
    NSArray<NSString *> *keys = identifyingItemKeys();
    for (NSString *key in keys) {
        id aValue = a[key];
        id bValue = b[key];
        if (aValue == nil || bValue == nil) {
            return false;
        }
        if (![aValue isEqual:bValue]) {
            return false;
        }
    }
    return true;
}

static void printData(NSDictionary *data) {
    NSArray<NSString *> *diffKeys = identifyingItemKeys();
    NSString *serialized = nil;
    if (previousData != nil && isSameItemIdentity(previousData, data)) {
        NSDictionary *diff = createDiff(previousData, data);
        if ([diff count] == 0) {
            return;
        }
        serialized = serializeData(diff, true);
    } else {
        serialized = serializeData(data, false);
    }
    if (serialized != nil) {
        previousData = [data copy];
        printOut(serialized);
    }
}

static void fail(NSString *message) {
    printErr(message);
    exit(1);
}

static void appForPID(int pid, void (^block)(NSRunningApplication *)) {
    if (pid <= 0) {
        return;
    }
    NSRunningApplication *process =
        [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (process == nil) {
        printErr(
            [NSString stringWithFormat:@"Failed to determine bundle identifier "
                                       @"for process with PID %d",
                                       pid]);
        return;
    }
    if (process.bundleIdentifier == nil) {
        printErr([NSString
            stringWithFormat:
                @"The bundle identifier for process with PID %d is nil", pid]);
        return;
    }
    block(process);
}

static void appForNotification(NSNotification *notification,
                               void (^block)(NSRunningApplication *)) {
    NSDictionary *userInfo = notification.userInfo;
    id pidValue = userInfo[kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey];
    if (pidValue == nil) {
        return;
    }
    int pid = [pidValue intValue];
    appForPID(pid, block);
};

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

extern void test() {
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
    _mediaRemote.getNowPlayingInfo(_queue, ^(NSDictionary *information) {
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

extern void loop() {

    // TODO make debouncing optional and configurable

    __block NSMutableDictionary *liveData = [NSMutableDictionary dictionary];
    __block Debounce *debounce = [[Debounce alloc] initWithDelay:DEBOUNCE_DELAY
                                                           queue:_queue];

    void (^handle)() = ^{
      if (liveData[kBundleIdentifier] != nil && liveData[kPlaying] != nil &&
          liveData[kTitle] != nil) {
          NSLog(@"getNowPlayingApplicationIsPlaying = %@", liveData[kPlaying]);
          printData(liveData);
      }
    };

    void (^requestNowPlayingApplicationPID)() = ^{
      _mediaRemote.getNowPlayingApplicationPID(_queue, ^(int pid) {
        if (pid == 0) {
            printData([NSMutableDictionary dictionary]);
            return;
        }
        appForPID(pid, ^(NSRunningApplication *process) {
          liveData[kBundleIdentifier] = process.bundleIdentifier;
          handle();
        });
      });
    };

    void (^requestNowPlayingApplicationIsPlaying)() = ^{
      _mediaRemote.getNowPlayingApplicationIsPlaying(_queue, ^(bool isPlaying) {
        NSLog(@"getNowPlayingApplicationIsPlaying = %d", isPlaying);
        liveData[kPlaying] = @(isPlaying);
        handle();
      });
    };

    void (^requestNowPlayingInfo)() = ^{
      _mediaRemote.getNowPlayingInfo(_queue, ^(NSDictionary *information) {
        if (information == nil) {
            return;
        }
        NSMutableDictionary *converted =
            convertNowPlayingInformation(information);
        // Transfer anything over from the existing live data.
        if (liveData[kBundleIdentifier] != nil) {
            converted[kBundleIdentifier] = liveData[kBundleIdentifier];
        }
        if (liveData[kPlaying] != nil) {
            converted[kPlaying] = liveData[kPlaying];
        }
        // Use the old artwork data, since often the MediaRemote framework
        // unloads the artwork and then loads it again shortly after.
        // Only do this when the items have the same identity.
        if (isSameItemIdentity(liveData, converted) &&
            liveData[kArtworkDataBase64] != nil &&
            liveData[kArtworkDataBase64] != [NSNull null] &&
            converted[kArtworkDataBase64] == [NSNull null]) {
            converted[kArtworkDataBase64] = liveData[kArtworkDataBase64];
        }
        [liveData addEntriesFromDictionary:converted];
        handle();
      });
    };

    void (^requestAll)() = ^{
      requestNowPlayingApplicationPID();
      requestNowPlayingApplicationIsPlaying();
      requestNowPlayingInfo();
    };

    void (^resetAll)() = ^{
      [liveData removeAllObjects];
    };

    void (^refreshAll)() = ^{
      resetAll();
      requestAll();
    };

    // FIXME Is this foolproof? This continues and registers observers
    // which might intervene with the initial three requests.
    requestAll();

    NSNotificationCenter *default_center = [NSNotificationCenter defaultCenter];
    NSNotificationCenter *shared_workscape_notification_center =
        [[NSWorkspace sharedWorkspace] notificationCenter];

    id is_playing_change_observer = [default_center
        addObserverForName:
            kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *notification) {
                  dispatch_async(_queue, ^() {
                    appForNotification(notification, ^(
                                           NSRunningApplication *process) {
                      id isPlayingValue =
                          notification.userInfo
                              [kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey];
                      if (isPlayingValue != nil) {
                          if (liveData[kBundleIdentifier] != nil &&
                              ![liveData[kBundleIdentifier]
                                  isEqual:process.bundleIdentifier]) {
                              // This is a different process, reset all data.
                              resetAll();
                          }
                          liveData[kBundleIdentifier] =
                              process.bundleIdentifier;
                          liveData[kPlaying] = @([isPlayingValue boolValue]);
                          NSLog(@"kMRMediaRemoteNowPlayingApplication"
                                @"IsPlayingDidChangeNotification = %d",
                                [isPlayingValue boolValue]);
                          if (liveData[kTitle] == nil) {
                              requestNowPlayingInfo();
                          }
                      }
                    });
                  });
                }];

    id info_change_observer = [default_center
        addObserverForName:kMRMediaRemoteNowPlayingInfoDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *notification) {
                  [debounce call:^{
                    appForNotification(
                        notification, ^(NSRunningApplication *process) {
                          if (liveData[kBundleIdentifier] != nil &&
                              ![liveData[kBundleIdentifier]
                                  isEqual:process.bundleIdentifier]) {
                              // This is a different process, reset all data.
                              resetAll();
                          }
                          if (liveData[kBundleIdentifier] == nil) {
                              requestNowPlayingApplicationPID();
                          }
                          if (liveData[kPlaying] == nil) {
                              requestNowPlayingApplicationIsPlaying();
                          }
                          requestNowPlayingInfo();
                        });
                  }];
                }];

    // Register notifications for when applications are closed.
    id app_termination_observer = [shared_workscape_notification_center
        addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *notification) {
                  dispatch_async(_queue, ^() {
                    NSDictionary *userInfo = [notification userInfo];
                    id bundleIdentifier =
                        userInfo[@"NSApplicationBundleIdentifier"];
                    if (bundleIdentifier != nil &&
                        liveData[kBundleIdentifier] == bundleIdentifier) {
                        // Refresh all data, since the application terminated.
                        refreshAll();
                    }
                  });
                }];

    _mediaRemote.registerForNowPlayingNotifications(_queue);

    // A little bit of a hack, but since CFRunLoopRun() returns without work,
    // we need to create a timer that ensures it doesn't exit and just idles.
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
        kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + INDEFINITELY, 0, 0, 0,
        NULL, NULL);
    CFRunLoopAddTimer(_runLoop, timer, kCFRunLoopCommonModes);
    CFRunLoopRunResult result =
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, INDEFINITELY, FALSE);

    _mediaRemote.unregisterForNowPlayingNotifications();

    [default_center removeObserver:is_playing_change_observer];
    [default_center removeObserver:info_change_observer];
    [shared_workscape_notification_center
        removeObserver:app_termination_observer];
}

extern void stop() {
    if (_runLoop) {
        CFRunLoopStop(_runLoop);
        _runLoop = NULL;
    }
}

static void handleSignal(int signal) {
    if (signal == SIGTERM) {
        stop();
    }
}

__attribute__((constructor)) static void init() {
    signal(SIGTERM, handleSignal);
    _mediaRemote = [[MediaRemote alloc] init];
    if (!_mediaRemote) {
        fail(@"Failed to initialize MediaRemote Framework");
        return;
    }
    _runLoop = CFRunLoopGetCurrent();
    _queue = dispatch_queue_create("mediaremote.mediaobserver",
                                   DISPATCH_QUEUE_SERIAL);
}

__attribute__((destructor)) static void teardown() { stop(); }

// FIXME Fix "peculiar media" (title is updated later than artist). Example:
/*
35.558Z Thirteen by Big Star on Camping Songs
36.091Z Good Vibrations (Remastered 2001) by Big Star on Camping Songs
36.204Z Good Vibrations (Remastered 2001) by Big Star on Camping Songs (+image)
36.624Z Good Vibrations (Remastered 2001) by The Beach Boys on Camping Songs
*/
