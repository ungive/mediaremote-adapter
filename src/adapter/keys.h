// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_ADAPTER_KEYS_H
#define MEDIAREMOTEADAPTER_ADAPTER_KEYS_H

#import <Foundation/Foundation.h>

// These keys identify a now playing item uniquely.
NSArray<NSString *> *identifyingStreamPayloadKeys(void);

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

#endif // MEDIAREMOTEADAPTER_ADAPTER_KEYS_H
