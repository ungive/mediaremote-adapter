// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

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

#import "MediaRemote.h"
#import "MediaRemoteAdapter.h"
#import "MediaRemoteAdapterKeys.h"

static const double INDEFINITELY = 1e10;

// These keys identify a now playing item uniquely.
static NSArray<NSString *> *identifyingItemKeys(void) {
    return @[ (NSString *)kTitle, (NSString *)kArtist, (NSString *)kAlbum ];
}

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
          id result =
              information[(__bridge NSString *)fromKey];
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

    setKey((NSString *)kTitle, (id)kMRMediaRemoteNowPlayingInfoTitle);
    setKey((NSString *)kArtist, (id)kMRMediaRemoteNowPlayingInfoArtist);
    setKey((NSString *)kAlbum, (id)kMRMediaRemoteNowPlayingInfoAlbum);
    setValue((NSString *)kDurationMicros, ^id {
      id duration =
          information[(NSString *)kMRMediaRemoteNowPlayingInfoDuration];
      if (duration != nil) {
          NSTimeInterval durationMicros = [duration doubleValue] * 1000 * 1000;
          return @(floor(durationMicros));
      }
      return nil;
    });
    setValue((NSString *)kElapsedTimeMicros, ^id {
      id elapsedTimeValue =
          information[(NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime];
      if (elapsedTimeValue != nil) {
          NSTimeInterval elapsedTimeMicros =
              [elapsedTimeValue doubleValue] * 1000 * 1000;
          return @(floor(elapsedTimeMicros));
      }
      return nil;
    });
    setValue((NSString *)kTimestampEpochMicros, ^id {
      NSDate *timestampValue =
          information[(NSString *)kMRMediaRemoteNowPlayingInfoTimestamp];
      if (timestampValue != nil) {
          NSTimeInterval timestampEpoch = [timestampValue timeIntervalSince1970];
          NSTimeInterval timestampEpochMicro = timestampEpoch * 1000 * 1000;
          return @(floor(timestampEpochMicro));
      }
      return nil;
    });
    setKey((NSString *)kArtworkMimeType,
           (id)kMRMediaRemoteNowPlayingInfoArtworkMIMEType);
    setValue((NSString *)kArtworkDataBase64, ^id {
      NSData *artworkDataValue =
          (NSData *)information[(NSString *)kMRMediaRemoteNowPlayingInfoArtworkData];
      if (artworkDataValue != nil) {
          return [artworkDataValue base64EncodedStringWithOptions:0];
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
    id pidValue = userInfo[(NSString *)kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey];
    if (pidValue == nil) {
        return;
    }
    int pid = [pidValue intValue];
    appForPID(pid, block);
}

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
    MRMediaRemoteGetNowPlayingInfo(_queue, ^(CFDictionaryRef information) {
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
            printErr(@"1");
            exit(0);
            return;
        }
    }

    // Print 0 when the process is not entitled.
    printErr(@"0");
    exit(0);
}

static void onNowPlayingInfoDidChange(NSNotification *notification) {
  MRMediaRemoteGetNowPlayingInfo(_queue, ^(CFDictionaryRef information) {
    NSMutableDictionary *data =
        convertNowPlayingInformation((NSDictionary *)information);
    MRMediaRemoteGetNowPlayingApplicationIsPlaying(
        _queue, ^(Boolean isPlaying) {
          [data setObject:@(isPlaying) forKey:kIsPlaying];
          MRMediaRemoteGetNowPlayingApplicationPID(_queue, ^(int pid) {
            appForPID(pid, ^(NSRunningApplication *application) {
              [data setObject:application.bundleIdentifier
                       forKey:kBundleIdentifier];
              [data setObject:application.localizedName
                       forKey:kName];
            });
            printData(data);
          });
        });
  });
}

static void onNowPlayingApplicationIsPlayingDidChange(
    NSNotification *notification) {
  NSDictionary *userInfo = notification.userInfo;
  if (userInfo == nil) {
    return;
  }
  id isPlayingValue =
      userInfo[(NSString *)
                   kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey];
  if (isPlayingValue == nil) {
    return;
  }
  BOOL isPlaying = [isPlayingValue boolValue];
  appForNotification(notification, ^(NSRunningApplication *application) {
    MRMediaRemoteGetNowPlayingInfo(_queue, ^(CFDictionaryRef information) {
      NSMutableDictionary *data = convertNowPlayingInformation((NSDictionary *)information);
      [data setObject:@(isPlaying) forKey:kIsPlaying];
      [data setObject:application.bundleIdentifier forKey:kBundleIdentifier];
      [data setObject:application.localizedName forKey:kName];
      printData(data);
    });
  });
}

void loop(void) {
  _queue = dispatch_queue_create("mediaremote-adapter", NULL);
  _runLoop = CFRunLoopGetCurrent();

  MRMediaRemoteRegisterForNowPlayingNotifications(_queue);

  [[NSNotificationCenter defaultCenter]
      addObserverForName:(NSString *)
                             kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification
                  object:nil
                   queue:nil
              usingBlock:^(NSNotification * _Nonnull note) {
                onNowPlayingApplicationIsPlayingDidChange(note);
              }];

  onNowPlayingInfoDidChange(nil);

  [[NSNotificationCenter defaultCenter]
      addObserverForName:(NSString *)kMRMediaRemoteNowPlayingInfoDidChangeNotification
                  object:nil
                   queue:nil
              usingBlock:^(NSNotification * _Nonnull note) {
                onNowPlayingInfoDidChange(note);
              }];

  CFRunLoopRun();
}

static void initialize_for_command() {
    dispatch_queue_t queue = dispatch_queue_create("mediaremote-adapter-command", NULL);
    MRMediaRemoteRegisterForNowPlayingNotifications(queue);
    // We might need a small delay for the registration to complete.
    // This is a guess, but a common pattern with async registrations.
    [NSThread sleepForTimeInterval:0.1];
}

void play(void) { 
    initialize_for_command();
    MRMediaRemoteSendCommand(kMRPlay, nil); 
}
void pause_command(void) { 
    initialize_for_command();
    MRMediaRemoteSendCommand(kMRPause, nil); 
}
void toggle_play_pause(void) { 
    initialize_for_command();
    MRMediaRemoteSendCommand(kMRTogglePlayPause, nil); 
}
void next_track(void) { 
    initialize_for_command();
    MRMediaRemoteSendCommand(kMRNextTrack, nil); 
}
void previous_track(void) { 
    initialize_for_command();
    MRMediaRemoteSendCommand(kMRPreviousTrack, nil); 
}
void stop_command(void) { 
    initialize_for_command();
    MRMediaRemoteSendCommand(kMRStop, nil); 
}

void set_time_from_env(void) {
    const char *seconds_str = getenv("MEDIAREMOTE_SET_TIME");
    if (seconds_str == NULL) {
        printErrf(@"[ERROR] MEDIAREMOTE_SET_TIME environment variable not set.");
        return;
    }
    double seconds = atof(seconds_str);
    initialize_for_command();
    MRMediaRemoteSetElapsedTime(seconds);
}

// FIXME Fix "peculiar media" (title is updated later than artist). Example:
/*
35.558Z Thirteen by Big Star on Camping Songs
36.091Z Good Vibrations (Remastered 2001) by Big Star on Camping Songs
36.204Z Good Vibrations (Remastered 2001) by Big Star on Camping Songs (+image)
36.624Z Good Vibrations (Remastered 2001) by The Beach Boys on Camping Songs
*/

static void handleSignal(int signal) {
    if (signal == SIGTERM) {
        CFRunLoopStop(_runLoop);
        _runLoop = NULL;
    }
}

__attribute__((constructor)) static void init() {
    signal(SIGTERM, handleSignal);
}

__attribute__((destructor)) static void teardown() {
    if (_runLoop) {
        CFRunLoopStop(_runLoop);
        _runLoop = NULL;
    }
}
