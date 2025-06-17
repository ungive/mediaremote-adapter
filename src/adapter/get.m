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

void adapter_get() {

    id semaphore = dispatch_semaphore_create(0);

    g_mediaRemote.getNowPlayingInfo(
        g_dispatchQueue, ^(NSDictionary *information) {
          NSDictionary *converted = convertNowPlayingInformation(information);
          BOOL allValuesAreNull = YES;
          for (id key in converted) {
              id value = converted[key];
              if (![value isKindOfClass:[NSNull class]]) {
                  allValuesAreNull = NO;
                  break;
              }
          }
          NSString *result = nil;
          if (!allValuesAreNull) {
              result = serializeJsonSafe(converted);
          } else {
              result = @"null";
          }
          if (!result) {
              fail(@"Failed to serialize now playing information");
          }
          printOut(result);
          dispatch_semaphore_signal(semaphore);
        });

    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, GET_TIMEOUT_MILLIS * NSEC_PER_MSEC);
    long result = dispatch_semaphore_wait(semaphore, timeout);
    if (result != 0) {
        printErrf(@"Response from MRMediaRemoteGetNowPlayingInfo timed out "
                  @"after @d milliseconds",
                  GET_TIMEOUT_MILLIS);
        exit(1);
    }
    dispatch_release(semaphore);
}
