// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#import "keys.h"

NSArray<NSString *> *mandatoryPayloadKeys(void) {
    return @[ kBundleIdentifier, kTitle, kPlaying ];
}

bool allMandatoryPayloadKeysSet(NSDictionary *data) {
    NSArray<NSString *> *keys = mandatoryPayloadKeys();
    for (NSString *key in keys) {
        if (data[key] == nil || data[key] == [NSNull null]) {
            return false;
        }
    }
    return true;
}

NSArray<NSString *> *identifyingPayloadKeys(void) {
    return @[ kBundleIdentifier, kTitle, kArtist, kAlbum ];
}

NSString *kBundleIdentifier = @"bundleIdentifier";
NSString *kPlaying = @"playing";
NSString *kTitle = @"title";
NSString *kArtist = @"artist";
NSString *kAlbum = @"album";
NSString *kDurationMicros = @"durationMicros";
NSString *kElapsedTimeMicros = @"elapsedTimeMicros";
NSString *kTimestampEpochMicros = @"timestampEpochMicros";
NSString *kArtworkMimeType = @"artworkMimeType";
NSString *kArtworkDataBase64 = @"artworkDataBase64";
