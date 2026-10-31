// Copyright (c) 2026 barissglc
// This file is licensed under the BSD 3-Clause License.

#import "adapter/feedback.h"
#import "MediaRemoteAdapter.h"
#import "adapter/globals.h"
#import "adapter/keys.h"

NSDictionary *feedbackStateForCommands(
    NSArray *commands,
    MRMediaRemoteCommandInfoGetCommand_t commandID,
    MRMediaRemoteCommandInfoGetEnabled_t enabled,
    MRMediaRemoteCommandInfoCopyValueForKey_t copyValue) {
    // The current MediaRemote identifier of MPRemoteCommandCenter.likeCommand.
    const int likeCommand = 21;
    for (id command in commands) {
        if (commandID(command) != likeCommand) continue;
        BOOL supported = enabled(command);
        id active = CFBridgingRelease(copyValue(
            command, CFSTR("kMRMediaRemoteCommandInfoIsActiveKey")));
        return @{
            kMRASupportsIsLiked : supported ? @YES : @NO,
            kMRAIsLiked : (supported && [active isKindOfClass:NSNumber.class] && [active boolValue]) ? @YES : @NO
        };
    }
    return @{kMRASupportsIsLiked : @NO, kMRAIsLiked : @NO};
}

void addMissingFeedbackState(NSMutableDictionary *metadata, NSDictionary *feedback) {
    for (NSString *key in @[kMRASupportsIsLiked, kMRAIsLiked]) {
        if (!metadata[key] && feedback[key]) metadata[key] = feedback[key];
    }
}

void requestFeedbackState(dispatch_queue_t queue,
                          void (^completion)(NSDictionary *state, int pid)) {
    if (!g_mediaRemote.copySupportedCommands ||
        !g_mediaRemote.commandInfoGetCommand ||
        !g_mediaRemote.commandInfoGetEnabled ||
        !g_mediaRemote.commandInfoCopyValueForKey) {
        completion(nil, 0);
        return;
    }
    g_mediaRemote.getNowPlayingApplicationPID(queue, ^(int before) {
      if (before <= 0) {
          completion(nil, 0);
          return;
      }
      g_mediaRemote.copySupportedCommands(queue, ^(NSArray *commands) {
        NSDictionary *state = feedbackStateForCommands(
            commands, g_mediaRemote.commandInfoGetCommand,
            g_mediaRemote.commandInfoGetEnabled,
            g_mediaRemote.commandInfoCopyValueForKey);
        g_mediaRemote.getNowPlayingApplicationPID(queue, ^(int after) {
          completion(before == after ? state : nil, after);
        });
      });
    });
}
