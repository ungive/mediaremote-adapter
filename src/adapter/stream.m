// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#import "MediaRemoteAdapter.h"
#import "adapter/globals.h"
#import "adapter/keys.h"
#import "adapter/now_playing.h"
#import "private/MediaRemote.h"
#import "utility/Debounce.h"
#import "utility/helpers.h"

#ifndef DEBOUNCE_DELAY_MILLIS
#define DEBOUNCE_DELAY_MILLIS 0
#endif

static const double INDEFINITELY = 1e10;

static CFRunLoopRef g_runLoop = NULL;

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
    NSArray<NSString *> *keys = identifyingStreamPayloadKeys();
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
    NSArray<NSString *> *diffKeys = identifyingStreamPayloadKeys();
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

extern void adapter_stream() {

    static const int debounce_delay_millis = (DEBOUNCE_DELAY_MILLIS);
#ifndef NDEBUG
    if (debounce_delay_millis > 0) {
        // NSLog(@"Using a debounce delay of %d milliseconds",
        //       debounce_delay_millis);
    }
#endif // !NDEBUG

    __block NSMutableDictionary *liveData = [NSMutableDictionary dictionary];
    __block Debounce *debounce =
        [[Debounce alloc] initWithDelay:(debounce_delay_millis / 1000.0)
                                  queue:g_dispatchQueue];

    void (^handle)() = ^{
      NSArray<NSString *> *keys = mandatoryStreamPayloadKeys();
      bool allPresent = true;
      for (NSString *key in keys) {
          if (liveData[key] == nil || liveData[key] == [NSNull null]) {
              allPresent = false;
              break;
          }
      }
      if (allPresent) {
          // NSLog(@"getNowPlayingApplicationIsPlaying = %@",
          // liveData[kPlaying]);
          printData(liveData);
      }
    };

    void (^requestNowPlayingApplicationPID)() = ^{
      g_mediaRemote.getNowPlayingApplicationPID(g_dispatchQueue, ^(int pid) {
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
      g_mediaRemote.getNowPlayingApplicationIsPlaying(
          g_dispatchQueue, ^(bool isPlaying) {
            // NSLog(@"getNowPlayingApplicationIsPlaying = %d", isPlaying);
            liveData[kPlaying] = @(isPlaying);
            handle();
          });
    };

    void (^requestNowPlayingInfo)() = ^{
      g_mediaRemote.getNowPlayingInfo(
          g_dispatchQueue, ^(NSDictionary *information) {
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
                  dispatch_async(g_dispatchQueue, ^() {
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
                          // NSLog(@"kMRMediaRemoteNowPlayingApplication"
                          //       @"IsPlayingDidChangeNotification = %d",
                          //       [isPlayingValue boolValue]);
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
                  dispatch_async(g_dispatchQueue, ^() {
                    NSDictionary *userInfo = [notification userInfo];
                    id bundleIdentifier =
                        userInfo[@"NSApplicationBundleIdentifier"];
                    if (bundleIdentifier != nil &&
                        [bundleIdentifier
                            isEqual:liveData[kBundleIdentifier]]) {
                        // Refresh all data, since the application terminated.
                        refreshAll();
                    }
                  });
                }];

    g_mediaRemote.registerForNowPlayingNotifications(g_dispatchQueue);

    // A little bit of a hack, but since CFRunLoopRun() returns without work,
    // we need to create a timer that ensures it doesn't exit and just idles.
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
        kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + INDEFINITELY, 0, 0, 0,
        NULL, NULL);
    CFRunLoopAddTimer(g_runLoop, timer, kCFRunLoopCommonModes);
    CFRunLoopRunResult result =
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, INDEFINITELY, FALSE);

    g_mediaRemote.unregisterForNowPlayingNotifications();

    [default_center removeObserver:is_playing_change_observer];
    [default_center removeObserver:info_change_observer];
    [shared_workscape_notification_center
        removeObserver:app_termination_observer];
}

extern void _adapter_stream_cancel() {
    if (g_runLoop) {
        CFRunLoopStop(g_runLoop);
        g_runLoop = NULL;
    }
}

static void handleSignal(int signal) {
    if (signal == SIGTERM) {
        _adapter_stream_cancel();
    }
}

__attribute__((constructor)) static void init() {
    g_runLoop = CFRunLoopGetCurrent();
    signal(SIGTERM, handleSignal);
}

__attribute__((destructor)) static void teardown() { _adapter_stream_cancel(); }

// FIXME Fix "peculiar media" (artist is updated later than title). Example:
/*
35.558 Thirteen by Big Star on Camping Songs
36.091 Good Vibrations (Remastered 2001) by Big Star on Camping Songs
36.204 Good Vibrations (Remastered 2001) by Big Star on Camping Songs (+image)
36.624 Good Vibrations (Remastered 2001) by The Beach Boys on Camping Songs
*/
