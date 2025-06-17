// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#include <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

#import "MediaRemoteAdapter.h"
#import "adapter/globals.h"
#import "adapter/keys.h"
#import "adapter/now_playing.h"
#import "utility/helpers.h"

#define GET_TIMEOUT_MILLIS 1000
#define JSON_NULL @"null"

void adapter_get() {

    id semaphore = dispatch_semaphore_create(0);

    static const int expected_calls = 3;

    __block int calls = 0; // thread-safe because the dispatch queue is serial.
    __block NSMutableDictionary *liveData = [NSMutableDictionary dictionary];

    void (^handle)() = ^{
      calls += 1;
      if (calls < expected_calls) {
          return;
      } else if (calls > expected_calls) {
          assert(false);
          return;
      }
      NSString *result = nil;
      if (liveData[kBundleIdentifier] == nil || liveData[kPlaying] == nil ||
          liveData[kTitle] == nil) {
          result = JSON_NULL;
      } else {
          result = serializeJsonSafe(liveData);
          if (!result) {
              fail(@"Failed to serialize now playing information");
          }
      }
      printOut(result);
      dispatch_semaphore_signal(semaphore);
    };

    g_mediaRemote.getNowPlayingApplicationPID(g_dispatchQueue, ^(int pid) {
      bool ok = appForPID(pid, ^(NSRunningApplication *process) {
        liveData[kBundleIdentifier] = process.bundleIdentifier;
        handle();
      });
      if (!ok) {
          handle();
      }
    });

    g_mediaRemote.getNowPlayingApplicationIsPlaying(
        g_dispatchQueue, ^(bool isPlaying) {
          liveData[kPlaying] = @(isPlaying);
          handle();
        });

    g_mediaRemote.getNowPlayingInfo(
        g_dispatchQueue, ^(NSDictionary *information) {
          NSDictionary *converted = convertNowPlayingInformation(information);
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
