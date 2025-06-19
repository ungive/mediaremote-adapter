#import "now_playing.h"

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
      id value = [NSNull null];
      if (information != nil) {
          id result = information[fromKey];
          if (result != nil) {
              value = result;
          }
      }
      [data setObject:value forKey:key];
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

    setKey(kTitle, kMRMediaRemoteNowPlayingInfoTitle);
    setKey(kArtist, kMRMediaRemoteNowPlayingInfoArtist);
    setKey(kAlbum, kMRMediaRemoteNowPlayingInfoAlbum);
    setValue(kDurationMicros, ^id {
      id duration = information[kMRMediaRemoteNowPlayingInfoDuration];
      if (duration != nil) {
          NSTimeInterval durationMicros = [duration doubleValue] * 1000 * 1000;
          return @(floor(durationMicros));
      }
      return nil;
    });
    setValue(kElapsedTimeMicros, ^id {
      id elapsedTime = information[kMRMediaRemoteNowPlayingInfoElapsedTime];
      if (elapsedTime != nil) {
          NSTimeInterval elapsedTimeMicros =
              [elapsedTime doubleValue] * 1000 * 1000;
          return @(floor(elapsedTimeMicros));
      }
      return nil;
    });
    setValue(kTimestampEpochMicros, ^id {
      NSDate *timestamp = information[kMRMediaRemoteNowPlayingInfoTimestamp];
      if (timestamp != nil) {
          NSTimeInterval timestampEpoch = [timestamp timeIntervalSince1970];
          NSTimeInterval timestampEpochMicro = timestampEpoch * 1000 * 1000;
          return @(floor(timestampEpochMicro));
      }
      return nil;
    });
    setKey(kArtworkMimeType, kMRMediaRemoteNowPlayingInfoArtworkMIMEType);
    setValue(kArtworkDataBase64, ^id {
      NSData *artworkData =
          information[kMRMediaRemoteNowPlayingInfoArtworkData];
      if (artworkData != nil) {
          return [artworkData base64EncodedStringWithOptions:0];
      }
      return nil;
    });

    return data;
}
