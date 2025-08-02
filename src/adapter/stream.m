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

static CFRunLoopRef g_runLoop = NULL;

static NSString *serializeData(NSDictionary *data, BOOL diff, BOOL pretty) {
    return serializeJsonDictionarySafe(
        @{
            @"type" : @"data",
            @"diff" : @(diff),
            @"payload" : data ?: @{},
        },
        pretty);
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

static BOOL isSameItemIdentity(NSDictionary *a, NSDictionary *b) {
    NSArray<NSString *> *keys = identifyingPayloadKeys();
    for (NSString *key in keys) {
        id aValue = a[key];
        id bValue = b[key];
        if (aValue == nil && bValue == nil) {
            continue;
        }
        if (aValue == nil || bValue == nil) {
            return NO;
        }
        if (![aValue isEqual:bValue]) {
            return NO;
        }
    }
    return YES;
}

static NSDictionary *previousData = nil;

static void printData(NSDictionary *data, BOOL diff, BOOL pretty) {
    NSString *serialized = nil;
    if (diff && previousData != nil && isSameItemIdentity(previousData, data)) {
        NSDictionary *result = createDiff(previousData, data);
        if ([result count] == 0) {
            return;
        }
        serialized = serializeData(result, YES, pretty);
    } else {
        serialized = serializeData(data, NO, pretty);
    }
    if (serialized != nil) {
        if (diff) {
            previousData = [data copy];
        }
        // Print the serialized data without duplicates. Note that while this
        // can fail when the key order in the serialized JSON output changes,
        // it practically won't because if it did, there would also be a change
        // in values that needs to be reported.
        printOutUnique(serialized);
    }
    if (!diff) {
        previousData = nil;
    }
}

static void appForNotification(NSNotification *notification,
                               void (^block)(NSRunningApplication *)) {
    NSDictionary *userInfo = notification.userInfo;
    id pidValue = userInfo[kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey];
    if (pidValue != nil) {
        int pid = [pidValue intValue];
        appForPID(pid, block);
    } else {
        block(nil);
    }
};

extern void adapter_stream() {

    // Get ADAPTER_TEST_MODE as a boolean and set BOOL isTestMode
    BOOL isTestMode = NO;
    char *testModeEnv = getenv("ADAPTER_TEST_MODE");
    if (testModeEnv && strcmp(testModeEnv, "0") != 0 && strlen(testModeEnv) > 0) {
        isTestMode = YES;
    }

    int debounce_delay_millis = 0;
    NSNumber *debounce_option = getEnvOptionInt(@"debounce");
    if (debounce_option != nil) {
        debounce_delay_millis = [debounce_option intValue];
    }

    NSString *no_diff_option = getEnvOption(@"no_diff");
    NSString *micros_option = getEnvOption(@"micros");
    NSString *human_readable_option = getEnvOption(@"human-readable");

    __block NSMutableDictionary *liveData = [NSMutableDictionary dictionary];
    __block const Debounce *const debounce =
        [[Debounce alloc] initWithDelay:(debounce_delay_millis / 1000.0)
                                  queue:g_serialdispatchQueue];
    __block const BOOL no_diff = (no_diff_option != nil);
    __block const BOOL convert_micros = (micros_option != nil);
    __block const bool human_readable = (human_readable_option != nil);

    void (^localPrintData)(NSDictionary *) = ^(NSDictionary *data) {
      printData(data, !no_diff, human_readable);
    };

    void (^handle)() = ^{
      if (allMandatoryPayloadKeysSet(liveData)) {
          if (human_readable) {
              NSMutableDictionary *shallowClone =
                  [NSMutableDictionary dictionaryWithDictionary:liveData];
              makePayloadHumanReadable(shallowClone);
              localPrintData(shallowClone);
          } else {
              localPrintData(liveData);
          }
      } else {
          localPrintData(nil);
      }
    };

    void (^requestNowPlayingApplicationPID)() = ^{
      g_mediaRemote.getNowPlayingApplicationPID(
          g_serialdispatchQueue, ^(int pid) {
            if (pid == 0) {
                handle();
                return;
            }
            liveData[kMRAProcessIdentifier] = @(pid);
            bool ok = appForPID(pid, ^(NSRunningApplication *process) {
              if (process.bundleIdentifier != nil) {
                  liveData[kMRABundleIdentifier] = process.bundleIdentifier;
              }
              handle();
            });
            if (!ok) {
                handle();
            }
          });
    };

    void (^requestNowPlayingParentApplicationBundleIdentifier)() = ^{
      g_mediaRemote.getNowPlayingClient(g_serialdispatchQueue, ^(id client) {
        NSString *parentAppBundleID = nil;
        if (client && [client respondsToSelector:@selector
                              (parentApplicationBundleIdentifier)]) {
            parentAppBundleID = [client
                performSelector:@selector(parentApplicationBundleIdentifier)];
        }
        if (parentAppBundleID) {
            liveData[kMRAParentApplicationBundleIdentifier] = parentAppBundleID;
        } else {
            [liveData removeObjectForKey:kMRAParentApplicationBundleIdentifier];
        }
        handle();
      });
    };

    void (^requestNowPlayingApplicationIsPlaying)() = ^{
      g_mediaRemote.getNowPlayingApplicationIsPlaying(
          g_serialdispatchQueue, ^(bool isPlaying) {
            liveData[kMRAPlaying] = @(isPlaying);
            handle();
          });
    };

    void (^requestNowPlayingInfo)() = ^{
      g_mediaRemote.getNowPlayingInfo(g_serialdispatchQueue, ^(
                                          NSDictionary *information) {
        NSString *serviceIdentifier = information[kMRMediaRemoteNowPlayingInfoServiceIdentifier];
        if (!isTestMode && [serviceIdentifier isEqualToString:@"com.vandenbe.MediaRemoteAdapter.NowPlayingTestClient"]) {
            return;
        }
        NSMutableDictionary *converted =
            convertNowPlayingInformation(information, convert_micros, false);
        // Transfer anything over from the existing live data.
        if (liveData[kMRAProcessIdentifier] != nil) {
            converted[kMRAProcessIdentifier] = liveData[kMRAProcessIdentifier];
        }
        if (liveData[kMRABundleIdentifier] != nil) {
            converted[kMRABundleIdentifier] = liveData[kMRABundleIdentifier];
        }
        if (liveData[kMRAParentApplicationBundleIdentifier] != nil) {
            converted[kMRAParentApplicationBundleIdentifier] =
                liveData[kMRAParentApplicationBundleIdentifier];
        }
        if (liveData[kMRAPlaying] != nil) {
            converted[kMRAPlaying] = liveData[kMRAPlaying];
        }
        // Use the old artwork data, since often the MediaRemote framework
        // unloads the artwork and then loads it again shortly after.
        // Only do this when the items have the same identity.
        if (isSameItemIdentity(liveData, converted) &&
            liveData[kMRAArtworkData] != nil &&
            liveData[kMRAArtworkData] != [NSNull null] &&
            converted[kMRAArtworkData] == nil) {
            converted[kMRAArtworkData] = liveData[kMRAArtworkData];
        }
        [liveData setDictionary:converted];
        handle();
      });
    };

    void (^requestAll)() = ^{
      requestNowPlayingApplicationPID();
      requestNowPlayingParentApplicationBundleIdentifier();
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
    // which might intervene with the initial requests.
    requestAll();

    NSNotificationCenter *default_center = [NSNotificationCenter defaultCenter];
    NSNotificationCenter *shared_workscape_notification_center =
        [[NSWorkspace sharedWorkspace] notificationCenter];

    // TODO Refactor the below two callbacks. They share a lot of code.

    id is_playing_change_observer = [default_center
        addObserverForName:
            kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *notification) {
                  dispatch_async(g_serialdispatchQueue, ^() {
                    appForNotification(notification, ^(
                                           NSRunningApplication *process) {
                      if (process == nil) {
                          // The process for this notification could not be
                          // determined. Assume that there is no now playing
                          // application anymore.
                          resetAll();
                          handle();
                          return;
                      }
                      id isPlayingValue =
                          notification.userInfo
                              [kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey];
                      if (isPlayingValue == nil) {
                          return;
                      }
                      if (liveData[kMRABundleIdentifier] != nil &&
                          process.bundleIdentifier != nil &&
                          ![liveData[kMRABundleIdentifier]
                              isEqual:process.bundleIdentifier]) {
                          // This is a different process, reset all data.
                          resetAll();
                      }
                      if (liveData[kMRAProcessIdentifier] != nil &&
                          ![liveData[kMRAProcessIdentifier]
                              isEqual:@(process.processIdentifier)]) {
                          // This is a different process, reset all data.
                          resetAll();
                      }
                      liveData[kMRABundleIdentifier] = process.bundleIdentifier;
                      requestNowPlayingParentApplicationBundleIdentifier();
                      liveData[kMRAPlaying] = @([isPlayingValue boolValue]);
                      if (liveData[kMRATitle] == nil) {
                          requestNowPlayingInfo();
                      } else {
                          handle();
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
                    appForNotification(notification, ^(
                                           NSRunningApplication *process) {
                      if (process == nil) {
                          // The process for this notification could not be
                          // determined. Assume that there is no now playing
                          // application anymore.
                          resetAll();
                          handle();
                          return;
                      }
                      if (liveData[kMRABundleIdentifier] != nil &&
                          process.bundleIdentifier != nil &&
                          ![liveData[kMRABundleIdentifier]
                              isEqual:process.bundleIdentifier]) {
                          // This is a different process, reset all data.
                          resetAll();
                      }
                      if (liveData[kMRAProcessIdentifier] != nil &&
                          ![liveData[kMRAProcessIdentifier]
                              isEqual:@(process.processIdentifier)]) {
                          // This is a different process, reset all data.
                          resetAll();
                      }
                      if (liveData[kMRAProcessIdentifier] == nil) {
                          requestNowPlayingApplicationPID();
                      }
                      if (liveData[kMRAParentApplicationBundleIdentifier] ==
                          nil) {
                          requestNowPlayingParentApplicationBundleIdentifier();
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
                  dispatch_async(g_serialdispatchQueue, ^() {
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

    g_mediaRemote.registerForNowPlayingNotifications(g_serialdispatchQueue);

    CFRunLoopRun();

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
    }
}

static void handleSignal(int signal) {
    if (signal == SIGINT || signal == SIGTERM) {
        _adapter_stream_cancel();
    }
}

__attribute__((constructor)) static void init() {
    g_runLoop = CFRunLoopGetCurrent();
    signal(SIGINT, handleSignal);
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
