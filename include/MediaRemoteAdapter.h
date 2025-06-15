// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_ADAPTER_H
#define MEDIAREMOTEADAPTER_ADAPTER_H

#import <Foundation/Foundation.h>

// Tests whether the process is entitled to use the MediaRemote framework.
// Prints "1" to stdout when it is entitled and "0" otherwise.
extern void test();

// Streams MediaRemote now playing updates to stdout.
// Exits when the process receives a SIGTERM signal.
extern void loop();

// Stops the any active calls to loop().
extern void stop();

extern NSString *kBundleIdentifier;
extern NSString *kPlaying;
extern NSString *kTitle;
extern NSString *kArtist;
extern NSString *kAlbum;
extern NSString *kDurationMicros;
extern NSString *kElapsedTimeMicros;
extern NSString *kTimestampEpochMicros;
extern NSString *kArtworkMimeType;
extern NSString *kArtworkDataBase64;

#endif // MEDIAREMOTEADAPTER_ADAPTER_H
