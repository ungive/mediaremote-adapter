// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/sysctl.h>
#include <unistd.h>

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#import "MediaRemote.h"
#import "MediaRemoteAdapter.h"
#import "MediaRemoteAdapterKeys.h"

static CFRunLoopRef _runLoop = NULL;
static dispatch_queue_t _queue;
static NSDictionary *previousData = nil;
static dispatch_block_t _debounce_block = NULL;

// These keys identify a now playing item uniquely.
static NSArray<NSString *> *identifyingItemKeys(void) {
    return @[ (NSString *)kTitle, (NSString *)kArtist, (NSString *)kAlbum ];
}

static void printOut(NSString *message) {
    fprintf(stdout, "%s\n", [message UTF8String]);
    fflush(stdout);
}

static void printErr(NSString *message) {
    fprintf(stderr, "%s\n", [message UTF8String]);
    fflush(stderr);
}

static NSString *formatError(NSError *error) {
    return
        [NSString stringWithFormat:@"%@ (%@:%ld)", [error localizedDescription],
                                   [error domain], (long)[error code]];
}

static NSString *serializeData(NSDictionary *data, BOOL diff) {
    NSError *error;
    NSDictionary *wrappedData = @{
        @"type" : @"data",
        @"diff" : @(diff),
        @"payload" : data,
    };
    NSData *serialized = [NSJSONSerialization dataWithJSONObject:wrappedData
                                                         options:0
                                                           error:&error];
    if (!serialized) {
        printErr([NSString stringWithFormat:@"Failed for serialize data: %@",
                                            formatError(error)]);
        return nil;
    }
    return [[NSString alloc] initWithData:serialized
                                 encoding:NSUTF8StringEncoding];
}

static NSMutableDictionary *
convertNowPlayingInformation(NSDictionary *information) {
    NSMutableDictionary *data = [NSMutableDictionary dictionary];

    void (^setKey)(id, id) = ^(id key, id fromKey) {
      id value = [NSNull null];
      if (information != nil) {
          id result =
              information[fromKey];
          if (result != nil) {
              value = result;
          }
      }
      [data setObject:value forKey:key];
    };

    void (^setValue)(id, id (^)(void)) = ^(id key, id (^evaluate)(void)) {
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

    setKey((NSString *)kTitle, (id)kMRMediaRemoteNowPlayingInfoTitle);
    setKey((NSString *)kArtist, (id)kMRMediaRemoteNowPlayingInfoArtist);
    setKey((NSString *)kAlbum, (id)kMRMediaRemoteNowPlayingInfoAlbum);
    setValue((NSString *)kDurationMicros, ^id {
      id duration =
          information[(NSString *)kMRMediaRemoteNowPlayingInfoDuration];
      if (duration != nil) {
          NSTimeInterval durationMicros = [duration doubleValue] * 1000 * 1000;
          return @(floor(durationMicros));
      }
      return nil;
    });
    setValue((NSString *)kElapsedTimeMicros, ^id {
      id elapsedTimeValue =
          information[(NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime];
      if (elapsedTimeValue != nil) {
          NSTimeInterval elapsedTimeMicros =
              [elapsedTimeValue doubleValue] * 1000 * 1000;
          return @(floor(elapsedTimeMicros));
      }
      return nil;
    });
    setValue((NSString *)kTimestampEpochMicros, ^id {
      NSDate *timestampValue =
          information[(NSString *)kMRMediaRemoteNowPlayingInfoTimestamp];
      if (timestampValue != nil) {
          NSTimeInterval timestampEpoch = [timestampValue timeIntervalSince1970];
          NSTimeInterval timestampEpochMicro = timestampEpoch * 1000 * 1000;
          return @(floor(timestampEpochMicro));
      }
      return nil;
    });
    setKey((NSString *)kArtworkMimeType,
           (id)kMRMediaRemoteNowPlayingInfoArtworkMIMEType);
    setValue((NSString *)kArtworkDataBase64, ^id {
      NSData *artworkDataValue =
          (NSData *)information[(NSString *)kMRMediaRemoteNowPlayingInfoArtworkData];
      if (artworkDataValue != nil) {
          return [artworkDataValue base64EncodedStringWithOptions:0];
      }
      return nil;
    });

    return data;
}

static NSDictionary *createDiff(NSDictionary *a, NSDictionary *b) {
    NSMutableDictionary *diff = [NSMutableDictionary dictionary];
    NSMutableSet *allKeys = [NSMutableSet setWithArray:a.allKeys];
    [allKeys addObjectsFromArray:b.allKeys];
    for (id key in allKeys) {
        id oldValue = a[key];
        id newValue = b[key];
        if (![oldValue isEqual:newValue]) {
            diff[key] = newValue ?: [NSNull null];
        }
    }
    return [diff copy];
}

static bool isSameItemIdentity(NSDictionary *a, NSDictionary *b) {
    for (NSString *key in identifyingItemKeys()) {
        id aValue = a[key];
        id bValue = b[key];
        if (aValue == nil || bValue == nil || ![aValue isEqual:bValue]) {
            return false;
        }
    }
    return true;
}

static void printData(NSDictionary *data) {
    NSString *serialized = nil;
    if (previousData != nil && isSameItemIdentity(previousData, data)) {
        NSDictionary *diff = createDiff(previousData, data);
        if ([diff count] == 0) return;
        serialized = serializeData(diff, true);
    } else {
        serialized = serializeData(data, false);
    }
    if (serialized != nil) {
        previousData = [data copy];
        printOut(serialized);
    }
}

static void appForPID(int pid, void (^block)(NSRunningApplication *)) {
    if (pid <= 0) return;
    NSRunningApplication *process =
        [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (process != nil && process.bundleIdentifier != nil) {
        block(process);
    }
}

static void appForNotification(NSNotification *notification,
                               void (^block)(NSRunningApplication *)) {
    id pidValue = notification.userInfo[(NSString *)kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey];
    if (pidValue != nil) {
        appForPID([pidValue intValue], block);
    }
}


// C function implementations to be called from Perl
void bootstrap(void) {
    NSLog(@"[ObjC] bootstrap() called.");
    _queue = dispatch_queue_create("mediaremote-adapter", DISPATCH_QUEUE_SERIAL);
}

void loop(void) {
    NSLog(@"[ObjC] loop() called. Setting up run loop and notifications.");
    _runLoop = CFRunLoopGetCurrent();

    MRMediaRemoteRegisterForNowPlayingNotifications(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));

    void (^handler)(NSNotification *) = ^(NSNotification *notification) {
      NSLog(@"[ObjC] Received notification. Debouncing for 100ms.");

      // If there's an existing block scheduled, cancel it.
      if (_debounce_block) {
          dispatch_block_cancel(_debounce_block);
      }

      // Create a new block to be executed after the delay.
      _debounce_block = dispatch_block_create(0, ^{
          NSLog(@"[ObjC] Debounced block executing. Getting now playing info.");
          MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef information) {
              NSDictionary *nowPlayingInfo = (__bridge NSDictionary *)information;

              // If there's no information, or the dictionary is empty, do nothing.
              // This prevents wiping the UI with an empty state.
              if (nowPlayingInfo == nil || [nowPlayingInfo count] == 0) {
                  NSLog(@"[ObjC] Now playing info is nil or empty. Ignoring.");
                  return;
              }

              NSLog(@"[ObjC] Now playing info is not nil. Converting and printing.");
              NSMutableDictionary *data = convertNowPlayingInformation(nowPlayingInfo);
              appForNotification(notification, ^(NSRunningApplication *process) {
                  data[(NSString *)kBundleIdentifier] = process.bundleIdentifier;
                  data[(NSString *)kApplicationName] = process.localizedName;
              });
              printData(data);
          });
      });
      
      // Schedule the new block to run after a 100ms delay.
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), _queue, _debounce_block);
    };
    
    [[NSNotificationCenter defaultCenter]
        addObserverForName:(NSString *)kMRMediaRemoteNowPlayingInfoDidChangeNotification
                    object:nil
                     queue:nil
                usingBlock:handler];

    NSLog(@"[ObjC] Entering CFRunLoopRun()...");
    CFRunLoopRun();
    NSLog(@"[ObjC] CFRunLoopRun() exited."); // This should not happen in normal operation
}

void play(void) {
    NSLog(@"[ObjC] play() called.");
    MRMediaRemoteSendCommand(kMRPlay, nil);
}

void pause_command(void) {
    NSLog(@"[ObjC] pause_command() called.");
    MRMediaRemoteSendCommand(kMRPause, nil);
}

void toggle_play_pause(void) {
    NSLog(@"[ObjC] toggle_play_pause() called.");
    MRMediaRemoteSendCommand(kMRTogglePlayPause, nil);
}

void next_track(void) {
    NSLog(@"[ObjC] next_track() called.");
    MRMediaRemoteSendCommand(kMRNextTrack, nil);
}

void previous_track(void) {
    NSLog(@"[ObjC] previous_track() called.");
    MRMediaRemoteSendCommand(kMRPreviousTrack, nil);
}

void stop_command(void) {
    NSLog(@"[ObjC] stop_command() called.");
    MRMediaRemoteSendCommand(kMRStop, nil);
} 