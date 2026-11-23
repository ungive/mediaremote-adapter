// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#include "private/MediaRemote.h"
#include <limits.h>

#import <Foundation/Foundation.h>

#import "MediaRemoteAdapter.h"
#import "adapter/commands.h"
#import "adapter/env.h"
#import "adapter/globals.h"
#import "adapter/now_playing.h"
#import "utility/helpers.h"

#define SEND_TIMEOUT_MILLIS 2000

static void validateCommand(int command) {
    dispatch_group_t group = dispatch_group_create();

    __block NSArray *supportedCommands = nil;
    if (g_mediaRemote.copySupportedCommands) {
        dispatch_group_enter(group);
        g_mediaRemote.copySupportedCommands(
            g_serialdispatchQueue, ^(NSArray *commands) {
              supportedCommands = convertSupportedCommandsList(commands);
              dispatch_group_leave(group);
            });
    } else {
        printErr(@"Warning: Unable to verify whether the specified command is "
                 @"supported: This system does not support enumeration of "
                 @"supported commands. Continuing without validation");
        return;
    }

    dispatch_time_t timeout =
        dispatch_time(DISPATCH_TIME_NOW, SEND_TIMEOUT_MILLIS * NSEC_PER_MSEC);
    long waitResult = dispatch_group_wait(group, timeout);
    if (waitResult != 0) {
        printErrf(@"Warning: Validation of the specified command timed out "
                  @"after %d milliseconds. Continuing without validation",
                  SEND_TIMEOUT_MILLIS);
        return;
    }

    bool isSupported = false;
    bool isEnabled = false;
    NSString *commandName = nil;
    for (NSDictionary *supportedCommand in supportedCommands) {
        id identifier = [supportedCommand objectForKey:kMRACommand_Identifier];
        if (identifier == nil || ![identifier isKindOfClass:[NSNumber class]]) {
            continue;
        }
        if ([identifier intValue] != (int)command) {
            continue;
        }
        isSupported = true;
        id enabled = [supportedCommand objectForKey:kMRACommand_Enabled];
        if (enabled != nil && [enabled isKindOfClass:[NSNumber class]]) {
            isEnabled = [enabled boolValue];
        }
        id name = [supportedCommand objectForKey:kMRACommand_Name];
        if ([name isKindOfClass:[NSString class]]) {
            commandName = name;
        }
        break;
    }
    if (!isSupported) {
        failf(@"The specified command is not supported by the current "
              @"now playing application: %d",
              command);
    }
    if (!isEnabled) {
        failf(@"The specified command is disabled with the current now "
              @"playing application: %d%@",
              command,
              commandName ? [NSString stringWithFormat:@" (%@)", commandName]
                          : @"");
    }
}

void adapter_send(int command) {

    // TODO Allow sending a command to a specific application. That's definitely
    //  possible: https://github.com/ungive/mediaremote-adapter/issues/48
    // TODO Allow sending data/parameter values. What data can be sent though?
    //   A good number of real-world examples would be good to have.
    // TODO Can we get a success/failure result from MediaRemote?

    NSString *force_option = getEnvOption(@"force");
    const bool force = force_option != nil;

    if (!force) {
        validateCommand(command);
    }

    bool result = g_mediaRemote.sendCommand((MRCommand)command, nil);
    if (!result) {
        failf(@"Failed to send command %d", command);
    }

    waitForCommandCompletion();
}

static inline int send_0_command() {
    return getEnvFuncParamIntSafe(@"adapter_send", 0, @"command");
}

void adapter_send_env() { adapter_send(send_0_command()); }
