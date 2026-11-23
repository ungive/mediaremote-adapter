// Copyright (c) 2026 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#include "commands.h"

#import "MediaRemoteAdapter.h"
#import "adapter/globals.h"
#import "adapter/keys.h"

NSArray *convertSupportedCommandsList(NSArray *commands) {
    NSMutableArray *list = [NSMutableArray array];
    if (commands == nil) {
        return [list copy];
    }
    for (id command in commands) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];

        id commandId = [command respondsToSelector:@selector(command)]
                           ? [command valueForKey:@"command"]
                           : nil;
        if ([commandId isKindOfClass:[NSNumber class]]) {
            result[kMRACommand_Identifier] = commandId;
        } else if (g_mediaRemote.commandInfoGetCommand) {
            result[kMRACommand_Identifier] =
                @(g_mediaRemote.commandInfoGetCommand(command));
        } else {
            continue;
        }

        if ([command respondsToSelector:@selector(dictionaryRepresentation)]) {
            id representation = [command dictionaryRepresentation];
            id commandString =
                [representation isKindOfClass:[NSDictionary class]]
                    ? [(NSDictionary *)representation objectForKey:@"command"]
                    : nil;
            if ([commandString isKindOfClass:[NSString class]]) {
                result[kMRACommand_Name] = commandString;
            }
        }

        id enabled = [command respondsToSelector:@selector(enabled)]
                         ? [command valueForKey:@"enabled"]
                         : nil;
        if ([enabled isKindOfClass:[NSNumber class]]) {
            result[kMRACommand_Enabled] =
                [NSNumber numberWithBool:[enabled boolValue]];
        } else if (g_mediaRemote.commandInfoGetEnabled) {
            result[kMRACommand_Enabled] = [NSNumber
                numberWithBool:g_mediaRemote.commandInfoGetEnabled(command)];
        }

        if ([command respondsToSelector:@selector(options)]) {
            id options = [command valueForKey:@"options"];
            if ([options isKindOfClass:[NSDictionary class]]) {
                result[kMRACommand_Options] = options;
            }
        }

        [list addObject:result];
    }
    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a,
                                                  NSDictionary *b) {
      return [a[kMRACommand_Identifier] compare:b[kMRACommand_Identifier]];
    }];
    return [list copy];
}
