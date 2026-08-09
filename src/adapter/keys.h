// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_ADAPTER_KEYS_H
#define MEDIAREMOTEADAPTER_ADAPTER_KEYS_H

#import <Foundation/Foundation.h>

// These keys are mandatory and must never be null, empty or missing.
NSArray<NSString *> *mandatoryPayloadKeys(void);

// The mandatory keys for media without a title, i.e. everything returned by
// mandatoryPayloadKeys() except the title. Used when the caller opts into
// receiving sessions whose metadata carries no title (see the
// "allow-missing-title" option), which some players produce for untagged
// audio: the now playing client, its PID and its playback state are all
// known, only the metadata dictionary is empty.
NSArray<NSString *> *mandatoryPayloadKeysWithoutTitle(void);

// Checks whether all mandatory payload keys returned by mandatoryPayloadKeys()
// are present in the given payload dictionary and have a non-null value.
bool allMandatoryPayloadKeysSet(NSDictionary *data);

// Same as allMandatoryPayloadKeysSet(), but the title is not required when
// allowMissingTitle is true.
bool allMandatoryPayloadKeysSetAllowingMissingTitle(NSDictionary *data,
                                                    bool allowMissingTitle);

// These keys identify a now playing item uniquely.
NSArray<NSString *> *identifyingPayloadKeys(void);

#endif // MEDIAREMOTEADAPTER_ADAPTER_KEYS_H
