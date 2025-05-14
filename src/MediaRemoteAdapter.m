#include <stdio.h>
#include <stdlib.h>

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#import "Debounce.h"
#import "MediaRemote.h"
#import "MediaRemoteAdapter.h"

NSString *kBundleIdentifier = @"bundleIdentifier";
NSString *kPlaying = @"playing";
NSString *kTitle = @"title";
NSString *kArtist = @"artist";
NSString *kAlbum = @"album";
NSString *kDurationMicros = @"durationMicros";
NSString *kElapsedTimeMicros = @"elapsedTimeMicros";
NSString *kTimestampEpochMicros = @"timestampEpochMicros";
NSString *kArtworkMimeType = @"artworkMimeType";
NSString *kArtworkDataBase64 = @"artworkDataBase64";

static const double INDEFINITELY = 1e10;
static const double DEBOUNCE_DELAY = 0.1; // seconds

// These keys identify a now playing item uniquely.
NSArray<NSString *> *identifyingItemKeys(void) {
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
      id value = information[fromKey];
      if (value == nil) {
          value = [NSNull null];
      };
      [data setObject:value forKey:key];
    };

    void (^setValue)(id key, id (^)(void)) = ^(id key, id (^evaluate)(void)) {
      id value = evaluate();
      if (value) {
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

void appForPID(int pid, void (^block)(NSRunningApplication *)) {
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

void appForNotification(NSNotification *notification,
                        void (^block)(NSRunningApplication *)) {
    NSDictionary *userInfo = notification.userInfo;
    id pidValue = userInfo[kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey];
    if (pidValue == nil) {
        return;
    }
    int pid = [pidValue intValue];
    appForPID(pid, block);
};

@implementation MediaRemoteAdapter

+ (void)loop {

    __block NSMutableDictionary *liveData = [NSMutableDictionary dictionary];
    __block Debounce *debounce = [[Debounce alloc] initWithDelay:DEBOUNCE_DELAY
                                                           queue:_queue];

    void (^handle)() = ^{
      if (liveData[kBundleIdentifier] != nil && liveData[kPlaying] != nil &&
          liveData[kTitle] != nil) {
          printData(liveData);
      }
    };

    void (^requestNowPlayingApplicationPID)() = ^{
      _mediaRemote.getNowPlayingApplicationPID(_queue, ^(int pid) {
        appForPID(pid, ^(NSRunningApplication *process) {
          liveData[kBundleIdentifier] = process.bundleIdentifier;
          handle();
        });
      });
    };

    void (^requestNowPlayingApplicationIsPlaying)() = ^{
      _mediaRemote.getNowPlayingApplicationIsPlaying(_queue, ^(bool isPlaying) {
        liveData[kPlaying] = @(isPlaying);
        handle();
      });
    };

    void (^requestNowPlayingInfo)() = ^{
      _mediaRemote.getNowPlayingInfo(_queue, ^(NSDictionary *information) {
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

+ (void)stop {
    // not yet implemented
}

@end

__attribute__((constructor)) static void init() {
    _mediaRemote = [[MediaRemote alloc] init];
    if (!_mediaRemote) {
        fail(@"Failed to initialize MediaRemote Framework");
        return;
    }
    _runLoop = CFRunLoopGetCurrent();
    _queue = dispatch_queue_create("mediaremote.mediaobserver",
                                   DISPATCH_QUEUE_SERIAL);
}

__attribute__((destructor)) static void teardown() {
    // not yet implemented
}
