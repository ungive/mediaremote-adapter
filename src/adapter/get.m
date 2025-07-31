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

    NSString *micros_option = getEnvOption(@"micros");
    __block const bool convert_micros = micros_option != nil;

    NSString *human_readable_option = getEnvOption(@"human-readable");
    __block const bool human_readable = human_readable_option != nil;

    NSString *now_option = getEnvOption(@"now");
    __block const bool calculate_now = now_option != nil;

    id semaphore = dispatch_semaphore_create(0);

    static const int expected_calls = 4;

    __block int calls = 0; // thread-safe because the dispatch queue is serial.
    __block NSMutableDictionary *liveData = [NSMutableDictionary dictionary];

    // Check if we're in test mode via environment variable
    BOOL isTestMode = (getEnvOptionInt(@"ADAPTER_TEST_MODE")) ? YES : NO;

    // Note that this function MUST be called by all MediaRemote callbacks
    // below, even when invalid data is received or a recoverable error occurs.
    void (^handle)() = ^{
      calls += 1;
      if (calls < expected_calls) {
          return;
      } else if (calls > expected_calls) {
          assert(false);
          return;
      }

      if (human_readable) {
          makePayloadHumanReadable(liveData);
      }

      NSString *result = nil;
      if (!allMandatoryPayloadKeysSet(liveData)) {
          result = JSON_NULL;
      } else {
          result = serializeJsonDictionarySafe(liveData, human_readable);
          if (!result) {
              fail(@"Failed to serialize now playing information");
          }
      }
      printOut(result);
      dispatch_semaphore_signal(semaphore);
    };

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
      handle();
    });

    g_mediaRemote.getNowPlayingApplicationIsPlaying(
        g_serialdispatchQueue, ^(bool isPlaying) {
          liveData[kMRAPlaying] = @(isPlaying);
          handle();
        });

    g_mediaRemote.getNowPlayingInfo(
        g_serialdispatchQueue, ^(NSDictionary *information) {
          NSDictionary *converted = convertNowPlayingInformation(
              information, convert_micros, calculate_now);
          [liveData addEntriesFromDictionary:converted];
          handle();
        });

    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, GET_TIMEOUT_MILLIS * NSEC_PER_MSEC);
    long result = dispatch_semaphore_wait(semaphore, timeout);
    if (result != 0) {
        printErrf(@"Reading now playing information timed out "
                  @"after @d milliseconds",
                  GET_TIMEOUT_MILLIS);
        exit(1);
    }
    dispatch_release(semaphore);
}

extern void adapter_get_env() { adapter_get(); }
