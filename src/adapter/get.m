// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#include <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

#import "MediaRemoteAdapter.h"
#import "adapter/env.h"
#import "adapter/globals.h"
#import "adapter/keys.h"
#import "adapter/now_playing.h"
#import "utility/helpers.h"

#define GET_TIMEOUT_MILLIS 2000
#define JSON_NULL @"null"
#define SIMULATED_BUNDLE_ID @"com.example.bundle"

void adapter_get() {

    // Get ADAPTER_TEST_MODE as a boolean and set BOOL isTestMode
    BOOL isTestMode = NO;
    char *testModeEnv = getenv("ADAPTER_TEST_MODE");
    if (testModeEnv && strcmp(testModeEnv, "0") != 0 && strlen(testModeEnv) > 0) {
        isTestMode = YES;
    }

    NSString *micros_option = getEnvOption(@"micros");
    __block const bool convert_micros = micros_option != nil;

    NSString *human_readable_option = getEnvOption(@"human-readable");
    __block const bool human_readable = human_readable_option != nil;

    NSString *now_option = getEnvOption(@"now");
    __block const bool calculate_now = now_option != nil;

    __block NSMutableDictionary *liveData = [NSMutableDictionary dictionary];



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
        if (client && [client respondsToSelector:@selector(parentApplicationBundleIdentifier)]) {
            parentAppBundleID = [client performSelector:@selector(parentApplicationBundleIdentifier)];
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
    g_mediaRemote.getNowPlayingInfo(
        g_serialdispatchQueue, ^(NSDictionary *information) {
            NSString *serviceIdentifier = information[kMRMediaRemoteNowPlayingInfoServiceIdentifier];
            if (!isTestMode && [serviceIdentifier isEqualToString:@"com.vandenbe.MediaRemoteAdapter.NowPlayingTestClient"]) {
                [liveData removeAllObjects];
                dispatch_group_leave(group);
                return;
            }
            NSDictionary *converted = convertNowPlayingInformation(
                information, convert_micros, calculate_now);
            [liveData addEntriesFromDictionary:converted];
            dispatch_group_leave(group);
        });

    // Wait for all async callbacks or timeout
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, GET_TIMEOUT_MILLIS * NSEC_PER_MSEC);
    long result = dispatch_group_wait(group, timeout);

    if (result != 0) {
        printErrf(@"Reading now playing information timed out after %d milliseconds", GET_TIMEOUT_MILLIS);
        dispatch_release(group);
        return;
    }

    if (human_readable) {
        makePayloadHumanReadable(liveData);
    }

    NSString *resultStr = nil;
    if (!allMandatoryPayloadKeysSet(liveData)) {
        resultStr = JSON_NULL;
    } else {
        resultStr = serializeJsonDictionarySafe(liveData, human_readable);
        if (!resultStr) {
            fail(@"Failed to serialize now playing information");
        }
    }

    printOut(resultStr);

    dispatch_release(group);
}

extern void adapter_get_env() { adapter_get(); }
