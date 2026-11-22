// Copyright (c) 2026 barissglc
// This file is licensed under the BSD 3-Clause License.

#import "private/MediaRemote.h"
#import <Foundation/Foundation.h>

NSDictionary *
feedbackStateForCommands(NSArray *commands,
                         MRMediaRemoteCommandInfoGetCommand_t commandID,
                         MRMediaRemoteCommandInfoGetEnabled_t enabled,
                         MRMediaRemoteCommandInfoCopyValueForKey_t copyValue);

void requestFeedbackState(dispatch_queue_t queue,
                          void (^completion)(NSDictionary *state));
