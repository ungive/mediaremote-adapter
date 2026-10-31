// Copyright (c) 2026 barissglc
// This file is licensed under the BSD 3-Clause License.

#import <Foundation/Foundation.h>
#import "private/MediaRemote.h"

NSDictionary *feedbackStateForCommands(
    NSArray *commands,
    MRMediaRemoteCommandInfoGetCommand_t commandID,
    MRMediaRemoteCommandInfoGetEnabled_t enabled,
    MRMediaRemoteCommandInfoCopyValueForKey_t copyValue);

// A PID on both sides of the command query prevents attributing feedback
// from a newly active player to the metadata of the previous player.
void requestFeedbackState(dispatch_queue_t queue,
                          void (^completion)(NSDictionary *state, int pid));

// Command metadata fills gaps without overriding a player's explicit values.
void addMissingFeedbackState(NSMutableDictionary *metadata, NSDictionary *feedback);
