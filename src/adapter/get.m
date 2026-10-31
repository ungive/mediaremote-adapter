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

// Formats the payload in place and reports whether it is complete. Shared by
// the default and the per-application read path.
static bool preparePayload(NSMutableDictionary *data) {
    if (getEnvOption(@"human-readable") != nil) {
        makePayloadHumanReadable(data);
    }
    return allMandatoryPayloadKeysSet(
        data, getEnvOption(@"allow-missing-title") != nil);
}

#define TEST_CLIENT_BUNDLE_ID @"com.vandenbe.MediaRemoteAdapter.TestClient"

// Returns a list with every client that matches the bundle identifier, either
// by its own bundle identifier or by its parent application's. A single
// identifier can match more than one application: web browsers built on
// WebKit play media through the shared com.apple.WebKit.GPU helper, so while
// Safari and Orion are both playing, --bundle-id=com.apple.WebKit.GPU matches
// both of them. A plain get never has this ambiguity, since the system elects
// only one now playing application.
static NSArray *internal_get_for_bundle(NSString *bundleIdentifier) {
    MediaRemote *mr = g_mediaRemote;
    if (!mr.getNowPlayingClients || !mr.nowPlayingClientGetBundleIdentifier ||
        !mr.nowPlayingClientGetProcessIdentifier || !mr.getLocalOrigin ||
        !mr.nowPlayingPlayerPathCreate || !mr.getNowPlayingInfoForPlayer ||
        !mr.getPlaybackStateForPlayer) {
        fail(@"Reading a specific application is not supported on this system");
    }

    const bool convert_micros = getEnvOption(@"micros") != nil;
    const bool calculate_now = getEnvOption(@"now") != nil;
    const bool no_artwork = getEnvOption(@"no-artwork") != nil;

    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, GET_TIMEOUT_MILLIS * NSEC_PER_MSEC);

    __block NSArray *clients = nil;
    dispatch_semaphore_t clientsRead = dispatch_semaphore_create(0);
    mr.getNowPlayingClients(g_serialdispatchQueue, ^(NSArray *result) {
      clients = [result copy];
      dispatch_semaphore_signal(clientsRead);
    });
    if (dispatch_semaphore_wait(clientsRead, timeout) != 0) {
        fail(@"Reading now playing clients timed out");
    }

    NSMutableArray *results = [NSMutableArray array];
    for (id client in clients) {
        NSString *clientBundleID =
            (__bridge NSString *)mr.nowPlayingClientGetBundleIdentifier(client);
        NSString *parentBundleID = nil;
        if ([client respondsToSelector:@selector
                    (parentApplicationBundleIdentifier)]) {
            parentBundleID = [client
                performSelector:@selector(parentApplicationBundleIdentifier)];
        }
        if (![clientBundleID isEqualToString:bundleIdentifier] &&
            ![parentBundleID isEqualToString:bundleIdentifier]) {
            continue;
        }
        // The test client is not an actual now playing application.
        if ([clientBundleID isEqualToString:TEST_CLIENT_BUNDLE_ID] ||
            [parentBundleID isEqualToString:TEST_CLIENT_BUNDLE_ID]) {
            continue;
        }

        id playerPath = (__bridge_transfer id)mr.nowPlayingPlayerPathCreate(
            mr.getLocalOrigin(), client, nil);
        if (!playerPath) {
            continue;
        }

        __block NSDictionary *information = nil;
        __block unsigned int playbackState = 0;
        dispatch_group_t group = dispatch_group_create();
        dispatch_group_enter(group);
        mr.getNowPlayingInfoForPlayer(playerPath, !no_artwork,
                                      g_serialdispatchQueue,
                                      ^(NSDictionary *result, id artwork) {
                                        information = [result copy];
                                        dispatch_group_leave(group);
                                      });
        dispatch_group_enter(group);
        mr.getPlaybackStateForPlayer(playerPath, g_serialdispatchQueue,
                                     ^(unsigned int state) {
                                       playbackState = state;
                                       dispatch_group_leave(group);
                                     });
        if (dispatch_group_wait(group, timeout) != 0) {
            fail(@"Reading now playing information timed out");
        }

        NSString *serviceIdentifier =
            information[kMRMediaRemoteNowPlayingInfoServiceIdentifier];
        if ([serviceIdentifier isEqualToString:TEST_CLIENT_BUNDLE_ID]) {
            continue;
        }

        // Report the client's own identifiers, which may differ from the
        // requested one when it matched the parent application.
        NSMutableDictionary *data = [NSMutableDictionary dictionary];
        if (clientBundleID) {
            data[kMRABundleIdentifier] = clientBundleID;
        }
        if (parentBundleID) {
            data[kMRAParentApplicationBundleIdentifier] = parentBundleID;
        }
        int pid = mr.nowPlayingClientGetProcessIdentifier(client);
        if (pid > 0) {
            data[kMRAProcessIdentifier] = @(pid);
        }
        if (information) {
            [data addEntriesFromDictionary:convertNowPlayingInformation(
                                               information, convert_micros,
                                               calculate_now, no_artwork)];
        }
        // Ask the player for its playback state instead of deriving it from
        // the playback rate in the metadata, which some applications, like
        // Spotify, do not set. 1 is MRPlaybackStatePlaying.
        data[kMRAPlaying] = playbackState == 1 ? @YES : @NO;

        if (preparePayload(data)) {
            [results addObject:data];
        }
    }
    return results;
}

NSDictionary *internal_get(BOOL isTestMode) {
    NSString *micros_option = getEnvOption(@"micros");
    __block const bool convert_micros = micros_option != nil;

    NSString *now_option = getEnvOption(@"now");
    __block const bool calculate_now = now_option != nil;

    NSString *no_artwork_option = getEnvOption(@"no-artwork");
    const bool no_artwork = no_artwork_option != nil;

    // Reading a specific application is handled by internal_get_for_bundle.
    if (getEnvOption(@"bundle-id") != nil) {
        fail(@"The bundle-id option is not supported by the test command");
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

    if (!preparePayload(liveData)) {
        return nil;
    }

    return liveData;
}

void adapter_get() {
    NSString *bundle_id_option = getEnvOption(@"bundle-id");

    NSString *human_readable_option = getEnvOption(@"human-readable");
    const bool human_readable = human_readable_option != nil;

    // With --bundle-id the result is always a list, possibly empty, since more
    // than one application can match. Without it, it is the single now
    // playing application or null.
    id result = nil;
    if (bundle_id_option != nil) {
        if (bundle_id_option.length == 0) {
            fail(@"Missing value for option 'bundle-id'");
        }
        result = internal_get_for_bundle(bundle_id_option);
    } else {
        result = internal_get(NO);
    }

    NSString *resultStr = nil;
    if (!result) {
        resultStr = JSON_NULL;
    } else {
        resultStr = serializeJsonDictionarySafe(result, human_readable);
        if (!resultStr) {
            fail(@"Failed to serialize now playing information");
        }
    }

    printOut(resultStr);
}

extern void adapter_get_env() { adapter_get(); }
