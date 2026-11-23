// Copyright (c) 2026 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_COMMANDS_H
#define MEDIAREMOTEADAPTER_COMMANDS_H

#import <Foundation/Foundation.h>

// Converts the given list of supported commands that was provided by
// "g_mediaRemote.copySupportedCommands" to an array of serializable
// dictionaries with known key and value types.
NSArray *convertSupportedCommandsList(NSArray *commands);

#endif // MEDIAREMOTEADAPTER_COMMANDS_H
