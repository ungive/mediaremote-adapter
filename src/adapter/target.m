// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#import "adapter/target.h"
#import "adapter/env.h"
#import "utility/helpers.h"

void beginTargetApplication(void) {
    NSString *bundleIdentifier = getEnvOption(@"bundle_id");
    if (bundleIdentifier == nil) {
        return;
    }
    if (bundleIdentifier.length == 0) {
        fail(@"Missing value for option 'bundle-id'");
    }
    // Changing the daemon's election affects unrelated processes. Neither
    // local serialization nor cleanup can make that a safe targeting API.
    fail(@"Targeted commands are unsupported: changing the now playing "
          @"application would affect other processes");
}
