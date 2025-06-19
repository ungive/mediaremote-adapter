// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_UTILITY_NOW_PLAYING_H
#define MEDIAREMOTEADAPTER_UTILITY_NOW_PLAYING_H

#import <Foundation/Foundation.h>

// Requests information once so that the process runs long enough for the
// MediaRemote command to actually be sent to the now playing application.
void waitForCommandCompletion();

NSMutableDictionary *convertNowPlayingInformation(NSDictionary *information);

#endif // MEDIAREMOTEADAPTER_UTILITY_NOW_PLAYING_H
