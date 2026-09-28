// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#include <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

#import "MediaRemoteAdapter.h"
#import "adapter/env.h"
#import "adapter/get.h"
#import "adapter/globals.h"
#import "adapter/keys.h"
#import "adapter/now_playing.h"
#import "utility/helpers.h"

#define GET_TIMEOUT_MILLIS 2000
#define JSON_NULL @"null"

// Reads the now playing state of one specific application.
//
// MediaRemote elects a single now playing application, and the regular "get"
// path only ever reports that one. Every other application that registered
// with MediaRemote is still a now playing client though, and its state can be
// read through a player path built from the local origin and that client.
// Returns nil if no client with the given bundle identifier is registered.
static NSDictionary *internal_get_for_bundle(NSString *bundleIdentifier,
                                             bool convert_micros,
                                             bool calculate_now,
                                             bool no_artwork,
                                             BOOL isTestMode,
                                             BOOL *timedOut) {
    *timedOut = NO;
    MediaRemote *mr = g_mediaRemote;
    if (!mr.getNowPlayingClients || !mr.nowPlayingClientGetBundleIdentifier ||
        !mr.getLocalOrigin || !mr.nowPlayingPlayerPathCreate ||
        !mr.getNowPlayingInfoForPlayer) {
        fail(@"Reading a specific application is not supported on this system");
    }

    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, GET_TIMEOUT_MILLIS * NSEC_PER_MSEC);

    __block NSArray *clients = nil;
    dispatch_semaphore_t clientsDone = dispatch_semaphore_create(0);
    mr.getNowPlayingClients(g_serialdispatchQueue, ^(NSArray *result) {
      clients = [result copy];
      dispatch_semaphore_signal(clientsDone);
    });
    if (dispatch_semaphore_wait(clientsDone, timeout) != 0) {
        *timedOut = YES;
        return nil;
    }

    // Match the client itself first, then the application that hosts it:
    // browsers can register through a helper process whose own bundle
    // identifier differs from the browser's.
    id client = nil;
    for (id candidate in clients) {
        NSString *candidateID = (__bridge NSString *)
            mr.nowPlayingClientGetBundleIdentifier(candidate);
        if ([candidateID isEqualToString:bundleIdentifier]) {
            client = candidate;
            break;
        }
    }
    if (!client) {
        for (id candidate in clients) {
            if ([candidate respondsToSelector:@selector
                           (parentApplicationBundleIdentifier)] &&
                [[candidate
                    performSelector:@selector(parentApplicationBundleIdentifier)]
                    isEqualToString:bundleIdentifier]) {
                client = candidate;
                break;
            }
        }
    }
    if (!client) {
        return nil;
    }

    NSMutableDictionary *liveData = [NSMutableDictionary dictionary];
    liveData[kMRABundleIdentifier] = bundleIdentifier;
    if (mr.nowPlayingClientGetProcessIdentifier) {
        int pid = mr.nowPlayingClientGetProcessIdentifier(client);
        if (pid > 0) {
            liveData[kMRAProcessIdentifier] = @(pid);
        }
    }
    if ([client respondsToSelector:@selector(parentApplicationBundleIdentifier)]) {
        NSString *parent =
            [client performSelector:@selector(parentApplicationBundleIdentifier)];
        if (parent) {
            liveData[kMRAParentApplicationBundleIdentifier] = parent;
        }
    }

    id path = (__bridge_transfer id)mr.nowPlayingPlayerPathCreate(
        mr.getLocalOrigin(), client, nil);
    if (!path) {
        return nil;
    }

    __block NSDictionary *information = nil;
    __block BOOL isFromTestClient = NO;
    dispatch_group_t group = dispatch_group_create();

    dispatch_group_enter(group);
    mr.getNowPlayingInfoForPlayer(
        path, NULL, g_serialdispatchQueue, ^(NSDictionary *info, NSError *error) {
          NSString *serviceIdentifier =
              info[kMRMediaRemoteNowPlayingInfoServiceIdentifier];
          if (!isTestMode &&
              [serviceIdentifier
                  isEqualToString:@"com.vandenbe.MediaRemoteAdapter.TestClient"]) {
              isFromTestClient = YES;
          } else {
              information = [info copy];
          }
          dispatch_group_leave(group);
        });

    if (dispatch_group_wait(group, timeout) != 0) {
        *timedOut = YES;
        return nil;
    }
    if (isFromTestClient) {
        return nil;
    }

    if (information) {
        [liveData addEntriesFromDictionary:convertNowPlayingInformation(
                                               information, convert_micros,
                                               calculate_now, no_artwork)];
    }

    // A player that is not the elected now playing application has no
    // "is playing" flag of its own to query, but its playback rate says the
    // same: non-zero while playing, zero while paused.
    NSNumber *rate = information[kMRMediaRemoteNowPlayingInfoPlaybackRate];
    const bool playing =
        [rate isKindOfClass:[NSNumber class]] && rate.doubleValue > 0;
    liveData[kMRAPlaying] = playing ? @YES : @NO;

    return liveData;
}

NSDictionary *internal_get(BOOL isTestMode) {
    NSString *micros_option = getEnvOption(@"micros");
    __block const bool convert_micros = micros_option != nil;

    NSString *human_readable_option = getEnvOption(@"human-readable");
    __block const bool human_readable = human_readable_option != nil;

    NSString *now_option = getEnvOption(@"now");
    __block const bool calculate_now = now_option != nil;

    NSString *no_artwork_option = getEnvOption(@"no-artwork");
    const bool no_artwork = no_artwork_option != nil;

    NSString *allow_missing_title_option = getEnvOption(@"allow-missing-title");
    const bool allow_missing_title = allow_missing_title_option != nil;

    NSString *bundle_id_option = getEnvOption(@"bundle-id");
    if (bundle_id_option != nil) {
        if (bundle_id_option.length == 0) {
            fail(@"Missing value for option 'bundle-id'");
        }
        BOOL timedOut = NO;
        NSMutableDictionary *data = [internal_get_for_bundle(
            bundle_id_option, convert_micros, calculate_now, no_artwork,
            isTestMode, &timedOut) mutableCopy];
        if (timedOut) {
            printErrf(@"Reading now playing information timed out after %d "
                      @"milliseconds",
                      GET_TIMEOUT_MILLIS);
            return nil;
        }
        if (!data) {
            return nil;
        }
        if (human_readable) {
            makePayloadHumanReadable(data);
        }
        if (!allMandatoryPayloadKeysSet(data, allow_missing_title)) {
            return nil;
        }
        return data;
    }

    __block NSMutableDictionary *liveData = [NSMutableDictionary dictionary];
    __block BOOL isFromTestClient = NO;

    dispatch_group_t group = dispatch_group_create();

    // PID and Bundle Identifier
    dispatch_group_enter(group);
    g_mediaRemote.getNowPlayingApplicationPID(
        g_serialdispatchQueue, ^(int pid) {
          if (pid != 0) {
              liveData[kMRAProcessIdentifier] = @(pid);
              bool ok = appForPID(pid, ^(NSRunningApplication *process) {
                if (process.bundleIdentifier != nil) {
                    liveData[kMRABundleIdentifier] = process.bundleIdentifier;
                }
                dispatch_group_leave(group);
              });
              if (!ok) {
                  dispatch_group_leave(group);
              }
          } else {
              dispatch_group_leave(group);
          }
        });

    // Now Playing Client
    dispatch_group_enter(group);
    g_mediaRemote.getNowPlayingClient(g_serialdispatchQueue, ^(id client) {
      NSString *parentAppBundleID = nil;
      if (client && [client respondsToSelector:@selector
                            (parentApplicationBundleIdentifier)]) {
          parentAppBundleID = [client
              performSelector:@selector(parentApplicationBundleIdentifier)];
      }
      if (parentAppBundleID) {
          liveData[kMRAParentApplicationBundleIdentifier] = parentAppBundleID;
      }
      dispatch_group_leave(group);
    });

    // Is Playing
    dispatch_group_enter(group);
    g_mediaRemote.getNowPlayingApplicationIsPlaying(
        g_serialdispatchQueue, ^(bool isPlaying) {
          liveData[kMRAPlaying] = @(isPlaying);
          dispatch_group_leave(group);
        });

    dispatch_group_enter(group);
    g_mediaRemote.getNowPlayingInfo(g_serialdispatchQueue, ^(
                                        NSDictionary *information) {
      NSString *serviceIdentifier =
          information[kMRMediaRemoteNowPlayingInfoServiceIdentifier];
      if (!isTestMode &&
          [serviceIdentifier
              isEqualToString:@"com.vandenbe.MediaRemoteAdapter.TestClient"]) {
          isFromTestClient = YES;
          dispatch_group_leave(group);
          return;
      }
      NSDictionary *converted = convertNowPlayingInformation(
          information, convert_micros, calculate_now, no_artwork);
      [liveData addEntriesFromDictionary:converted];
      dispatch_group_leave(group);
    });

    // Wait for all async callbacks or timeout
    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, GET_TIMEOUT_MILLIS * NSEC_PER_MSEC);
    long result = dispatch_group_wait(group, timeout);

    if (result != 0) {
        printErrf(
            @"Reading now playing information timed out after %d milliseconds",
            GET_TIMEOUT_MILLIS);
        return nil;
    }

    if (isFromTestClient) {
        return nil;
    }

    if (human_readable) {
        makePayloadHumanReadable(liveData);
    }

    if (!allMandatoryPayloadKeysSet(liveData, allow_missing_title)) {
        return nil;
    }

    return liveData;
}

void adapter_get() {
    NSDictionary *liveData = internal_get(NO);

    NSString *micros_option = getEnvOption(@"micros");
    const bool convert_micros = micros_option != nil;

    NSString *human_readable_option = getEnvOption(@"human-readable");
    const bool human_readable = human_readable_option != nil;

    NSString *resultStr = nil;
    if (!liveData) {
        resultStr = JSON_NULL;
    } else {
        resultStr = serializeJsonDictionarySafe(liveData, human_readable);
        if (!resultStr) {
            fail(@"Failed to serialize now playing information");
        }
    }

    printOut(resultStr);
}

extern void adapter_get_env() { adapter_get(); }
