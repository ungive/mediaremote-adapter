// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#import "MediaRemoteAdapter.h"
#import "adapter/env.h"
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
    return serializeJsonDictionarySafe(@{
        @"type" : @"data",
        @"diff" : @(diff),
        @"payload" : data,
    });
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

static bool isSameItemIdentity(NSDictionary *a, NSDictionary *b) {
    NSArray<NSString *> *keys = identifyingPayloadKeys();
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

static NSDictionary *previousData = nil;

static void printData(NSDictionary *data, bool diff) {
    NSString *serialized = nil;
    if (diff && previousData != nil && isSameItemIdentity(previousData, data)) {
        NSDictionary *result = createDiff(previousData, data);
        if ([result count] == 0) {
            return;
        }
        serialized = serializeData(result, true);
    } else {
        serialized = serializeData(data, false);
    }
    if (serialized != nil) {
        if (diff) {
            previousData = [data copy];
        }
        printOut(serialized);
    }
    if (!diff) {
        previousData = nil;
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

    int debounce_delay_millis = 0;
    NSNumber *debounce_option = getEnvOptionInt(@"debounce");
    if (debounce_option != nil) {
        debounce_delay_millis = [debounce_option intValue];
    }

    NSString *no_diff_option = getEnvOption(@"no_diff");

    __block NSMutableDictionary *liveData = [NSMutableDictionary dictionary];
    __block const Debounce *const debounce =
        [[Debounce alloc] initWithDelay:(debounce_delay_millis / 1000.0)
                                  queue:g_dispatchQueue];
    __block const bool no_diff = no_diff_option != nil;

    void (^localPrintData)(NSDictionary *) = ^(NSDictionary *data) {
      printData(data, !no_diff);
    };

    void (^handle)() = ^{
      if (allMandatoryPayloadKeysSet(liveData)) {
          // NSLog(@"getNowPlayingApplicationIsPlaying = %@",
          // liveData[kPlaying]);
          localPrintData(liveData);
      }
    };

    void (^requestNowPlayingApplicationPID)() = ^{
      g_mediaRemote.getNowPlayingApplicationPID(g_dispatchQueue, ^(int pid) {
        if (pid == 0) {
            localPrintData([NSMutableDictionary dictionary]);
            return;
        }
        appForPID(pid, ^(NSRunningApplication *process) {
          liveData[kMRABundleIdentifier] = process.bundleIdentifier;
          handle();
        });
      });
    };

    void (^requestNowPlayingApplicationIsPlaying)() = ^{
      g_mediaRemote.getNowPlayingApplicationIsPlaying(
          g_dispatchQueue, ^(bool isPlaying) {
            // NSLog(@"getNowPlayingApplicationIsPlaying = %d", isPlaying);
            liveData[kMRAPlaying] = @(isPlaying);
            handle();
          });
    };

    void (^requestNowPlayingInfo)() = ^{
      g_mediaRemote.getNowPlayingInfo(g_dispatchQueue, ^(
                                          NSDictionary *information) {
        NSMutableDictionary *converted =
            convertNowPlayingInformation(information);
        // Transfer anything over from the existing live data.
        if (liveData[kMRABundleIdentifier] != nil) {
            converted[kMRABundleIdentifier] = liveData[kMRABundleIdentifier];
        }
        if (liveData[kMRAPlaying] != nil) {
            converted[kMRAPlaying] = liveData[kMRAPlaying];
        }
        // Use the old artwork data, since often the MediaRemote framework
        // unloads the artwork and then loads it again shortly after.
        // Only do this when the items have the same identity.
        if (isSameItemIdentity(liveData, converted) &&
            liveData[kMRAArtworkDataBase64] != nil &&
            liveData[kMRAArtworkDataBase64] != [NSNull null] &&
            converted[kMRAArtworkDataBase64] == [NSNull null]) {
            converted[kMRAArtworkDataBase64] = liveData[kMRAArtworkDataBase64];
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
                          if (liveData[kMRABundleIdentifier] != nil &&
                              ![liveData[kMRABundleIdentifier]
                                  isEqual:process.bundleIdentifier]) {
                              // This is a different process, reset all data.
                              resetAll();
                          }
                          liveData[kMRABundleIdentifier] =
                              process.bundleIdentifier;
                          liveData[kMRAPlaying] = @([isPlayingValue boolValue]);
                          // NSLog(@"kMRMediaRemoteNowPlayingApplication"
                          //       @"IsPlayingDidChangeNotification = %d",
                          //       [isPlayingValue boolValue]);
                          if (liveData[kMRATitle] == nil) {
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
                          if (liveData[kMRABundleIdentifier] != nil &&
                              ![liveData[kMRABundleIdentifier]
                                  isEqual:process.bundleIdentifier]) {
                              // This is a different process, reset all data.
                              resetAll();
                          }
                          if (liveData[kMRABundleIdentifier] == nil) {
                              requestNowPlayingApplicationPID();
                          }
                          if (liveData[kMRAPlaying] == nil) {
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
                            isEqual:liveData[kMRABundleIdentifier]]) {
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

extern void adapter_stream_env() { adapter_stream(); }

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
