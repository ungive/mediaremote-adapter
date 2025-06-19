// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#import "keys.h"

#import "MediaRemoteAdapter.h"

NSArray<NSString *> *mandatoryPayloadKeys(void) {
    return @[ kMRABundleIdentifier, kMRATitle, kMRAPlaying ];
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
    return @[ kMRABundleIdentifier, kMRATitle, kMRAArtist, kMRAAlbum ];
}

NSString *kMRABundleIdentifier = @"bundleIdentifier";
NSString *kMRAPlaying = @"playing";
NSString *kMRATitle = @"title";
NSString *kMRAArtist = @"artist";
NSString *kMRAAlbum = @"album";
NSString *kMRADurationMicros = @"durationMicros";
NSString *kMRAElapsedTimeMicros = @"elapsedTimeMicros";
NSString *kMRATimestampEpochMicros = @"timestampEpochMicros";
NSString *kMRAArtworkMimeType = @"artworkMimeType";
NSString *kMRAArtworkDataBase64 = @"artworkDataBase64";
