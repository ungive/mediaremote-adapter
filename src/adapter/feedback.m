// Copyright (c) 2026 barissglc
// This file is licensed under the BSD 3-Clause License.

#import "adapter/feedback.h"
#import "MediaRemoteAdapter.h"
#import "adapter/globals.h"

NSDictionary *
feedbackStateForCommands(NSArray *commands,
                         MRMediaRemoteCommandInfoGetCommand_t commandID,
                         MRMediaRemoteCommandInfoGetEnabled_t enabled,
                         MRMediaRemoteCommandInfoCopyValueForKey_t copyValue) {
    // The current MediaRemote identifier of MPRemoteCommandCenter.likeCommand.
    const int likeCommand = 21;
    for (id command in commands) {
        if (commandID(command) != likeCommand)
            continue;
        if (!enabled(command))
            return @{};

        id active = CFBridgingRelease(
            copyValue(command, CFSTR("kMRMediaRemoteCommandInfoIsActiveKey")));
        if ([active isKindOfClass:NSNumber.class]) {
            return @{
                kMRALikeCommandEnabled : @YES,
                kMRALikeCommandActive : [active boolValue] ? @YES : @NO
            };
        }
        return @{kMRALikeCommandEnabled : @YES};
    }
    return @{};
}

void requestFeedbackState(dispatch_queue_t queue,
                          void (^completion)(NSDictionary *state)) {
    if (!g_mediaRemote.copySupportedCommands ||
        !g_mediaRemote.commandInfoGetCommand ||
        !g_mediaRemote.commandInfoGetEnabled ||
        !g_mediaRemote.commandInfoCopyValueForKey) {
        completion(nil);
        return;
    }
    g_mediaRemote.copySupportedCommands(queue, ^(NSArray *commands) {
      completion(feedbackStateForCommands(
          commands, g_mediaRemote.commandInfoGetCommand,
          g_mediaRemote.commandInfoGetEnabled,
          g_mediaRemote.commandInfoCopyValueForKey));
    });
}
