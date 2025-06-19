#import "now_playing.h"

#import "MediaRemoteAdapter.h"
#import "adapter/globals.h"
#import "adapter/keys.h"
#import "private/MediaRemote.h"

#define WAIT_TIMEOUT_MILLIS 2000

void waitForCommandCompletion() {
    id semaphore = dispatch_semaphore_create(0);

    g_mediaRemote.getNowPlayingApplicationPID(g_dispatchQueue, ^(int pid) {
      dispatch_semaphore_signal(semaphore);
    });

    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, WAIT_TIMEOUT_MILLIS * NSEC_PER_MSEC);
    dispatch_semaphore_wait(semaphore, timeout);
    dispatch_release(semaphore);
}

NSMutableDictionary *convertNowPlayingInformation(NSDictionary *information) {
    NSMutableDictionary *data = [NSMutableDictionary dictionary];

    void (^setKey)(id, id) = ^(id key, id fromKey) {
      id value = nil;
      if (information != nil) {
          id result = information[fromKey];
          if (result != nil) {
              value = result;
          }
      }
      if (value != nil) {
          [data setObject:value forKey:key];
      }
    };

    void (^setValue)(id key, id (^)(void)) = ^(id key, id (^evaluate)(void)) {
      id value = nil;
      if (information != nil) {
          value = evaluate();
      }
      if (value != nil) {
          [data setObject:value forKey:key];
      } else {
          [data setObject:[NSNull null] forKey:key];
      }
    };

    setKey(kMRATitle, kMRMediaRemoteNowPlayingInfoTitle);
    setKey(kMRAArtist, kMRMediaRemoteNowPlayingInfoArtist);
    setKey(kMRAAlbum, kMRMediaRemoteNowPlayingInfoAlbum);
    setValue(kMRADurationMicros, ^id {
      id duration = information[kMRMediaRemoteNowPlayingInfoDuration];
      if (duration != nil) {
          NSTimeInterval durationMicros = [duration doubleValue] * 1000 * 1000;
          return @(floor(durationMicros));
      }
      return nil;
    });
    setValue(kMRAElapsedTimeMicros, ^id {
      id elapsedTime = information[kMRMediaRemoteNowPlayingInfoElapsedTime];
      if (elapsedTime != nil) {
          NSTimeInterval elapsedTimeMicros =
              [elapsedTime doubleValue] * 1000 * 1000;
          return @(floor(elapsedTimeMicros));
      }
      return nil;
    });
    setValue(kMRATimestampEpochMicros, ^id {
      NSDate *timestamp = information[kMRMediaRemoteNowPlayingInfoTimestamp];
      if (timestamp != nil) {
          NSTimeInterval timestampEpoch = [timestamp timeIntervalSince1970];
          NSTimeInterval timestampEpochMicro = timestampEpoch * 1000 * 1000;
          return @(floor(timestampEpochMicro));
      }
      return nil;
    });
    setKey(kMRAArtworkMimeType, kMRMediaRemoteNowPlayingInfoArtworkMIMEType);
    setKey(kMRAArtworkDataBase64, kMRMediaRemoteNowPlayingInfoArtworkData);

    return data;
}
