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

// Both paths validate and format payloads identically.
static NSDictionary *preparePayload(NSDictionary *data) {
    if (!data) return nil;
    NSMutableDictionary *result = [data mutableCopy];
    if (getEnvOption(@"human-readable") != nil) {
        makePayloadHumanReadable(result);
    }
    if (!allMandatoryPayloadKeysSet(result,
                                   getEnvOption(@"allow-missing-title") != nil)) {
        return nil;
    }
    return result;
}

// Return every matching client. Helper bundle identifiers can be shared by
// unrelated applications, so selecting only the first match loses sessions.
static NSArray *internal_get_for_bundle(NSString *bundleIdentifier) {
    MediaRemote *mr = g_mediaRemote;
    if (!mr.getNowPlayingClients || !mr.nowPlayingClientGetBundleIdentifier ||
        !mr.nowPlayingClientGetProcessIdentifier || !mr.getLocalOrigin ||
        !mr.nowPlayingPlayerPathCreate || !mr.getNowPlayingInfoForPlayer ||
        !mr.getPlaybackStateForPlayer) {
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
        fail(@"Reading now playing clients timed out");
    }

    NSMutableArray *results = [NSMutableArray array];
    for (id client in clients) {
        NSString *clientID = (__bridge NSString *)
            mr.nowPlayingClientGetBundleIdentifier(client);
        NSString *parent = nil;
        if ([client respondsToSelector:@selector(parentApplicationBundleIdentifier)]) {
            parent = [client performSelector:@selector(parentApplicationBundleIdentifier)];
        }
        if (![clientID isEqualToString:bundleIdentifier] &&
            ![parent isEqualToString:bundleIdentifier]) continue;
        if ([clientID isEqualToString:@"com.vandenbe.MediaRemoteAdapter.TestClient"] ||
            [parent isEqualToString:@"com.vandenbe.MediaRemoteAdapter.TestClient"]) continue;

        id path = (__bridge_transfer id)mr.nowPlayingPlayerPathCreate(
            mr.getLocalOrigin(), client, nil);
        if (!path) continue;
        __block NSDictionary *information = nil;
        __block NSError *readError = nil;
        __block unsigned int state = 0;
        dispatch_group_t group = dispatch_group_create();
        dispatch_group_enter(group);
        mr.getNowPlayingInfoForPlayer(path, NULL, g_serialdispatchQueue,
            ^(NSDictionary *info, NSError *error) {
                information = [info copy];
                readError = error;
                dispatch_group_leave(group);
            });
        dispatch_group_enter(group);
        mr.getPlaybackStateForPlayer(path, g_serialdispatchQueue,
            ^(unsigned int playbackState) {
                state = playbackState;
                dispatch_group_leave(group);
            });
        if (dispatch_group_wait(group, timeout) != 0) {
            fail(@"Reading now playing information timed out");
        }
        if (readError) {
            failf(@"Reading now playing application failed: %@", readError);
        }
        if ([information[kMRMediaRemoteNowPlayingInfoServiceIdentifier]
                isEqualToString:@"com.vandenbe.MediaRemoteAdapter.TestClient"]) continue;
        NSMutableDictionary *data = [NSMutableDictionary dictionary];
        // Report the actual client identity, not the requested parent ID.
        if (clientID) data[kMRABundleIdentifier] = clientID;
        if (parent) data[kMRAParentApplicationBundleIdentifier] = parent;
        int pid = mr.nowPlayingClientGetProcessIdentifier(client);
        if (pid > 0) data[kMRAProcessIdentifier] = @(pid);
        if (information) {
            [data addEntriesFromDictionary:convertNowPlayingInformation(
                information, getEnvOption(@"micros") != nil,
                getEnvOption(@"now") != nil, getEnvOption(@"no-artwork") != nil)];
        }
        // MRPlaybackStatePlaying = 1. Metadata playbackRate may be absent
        // even while playing (Spotify), so it is not a playback-state query.
        data[kMRAPlaying] = state == 1 ? @YES : @NO;
        NSDictionary *prepared = preparePayload(data);
        if (prepared) [results addObject:prepared];
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

    if (getEnvOption(@"bundle-id") != nil) {
        fail(@"Bundle targeting is not supported in internal test mode");
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

    return preparePayload(liveData);
}

void adapter_get() {
    NSString *bundleIdentifier = getEnvOption(@"bundle-id");
    id result;
    if (bundleIdentifier != nil) {
        if (bundleIdentifier.length == 0) {
            fail(@"Missing value for option 'bundle-id'");
        }
        result = internal_get_for_bundle(bundleIdentifier);
    } else {
        result = internal_get(NO);
    }
    NSString *resultStr = result
        ? serializeJsonDictionarySafe(result, getEnvOption(@"human-readable") != nil)
        : JSON_NULL;
    if (!resultStr) fail(@"Failed to serialize now playing information");
    printOut(resultStr);
}

extern void adapter_get_env() { adapter_get(); }
