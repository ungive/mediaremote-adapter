// Copyright (c) 2026 barissglc
// This file is licensed under the BSD 3-Clause License.

#import "adapter/feedback.h"
#import "adapter/globals.h"
#import <Foundation/Foundation.h>

@interface TestCommand : NSObject
@property int identifier;
@property BOOL enabled;
@property id active;
@end
@implementation TestCommand
@end

static int commandID(id command) { return ((TestCommand *)command).identifier; }
static Boolean enabled(id command) { return ((TestCommand *)command).enabled; }
static CFTypeRef active(id command, CFStringRef key) {
    NSCAssert(CFEqual(key, CFSTR("kMRMediaRemoteCommandInfoIsActiveKey")),
              @"wrong state key");
    return CFBridgingRetain(((TestCommand *)command).active);
}

static BOOL missingAPI;
static NSArray *testCommands;
static void readCommands(dispatch_queue_t queue,
                         void (^completion)(NSArray *)) {
    (void)queue;
    completion(testCommands);
}

@interface TestMediaRemote : MediaRemote
@end
@implementation TestMediaRemote
- (MRMediaRemoteCopySupportedCommands_t)copySupportedCommands {
    return missingAPI ? NULL : readCommands;
}
- (MRMediaRemoteCommandInfoGetCommand_t)commandInfoGetCommand {
    return commandID;
}
- (MRMediaRemoteCommandInfoGetEnabled_t)commandInfoGetEnabled {
    return enabled;
}
- (MRMediaRemoteCommandInfoCopyValueForKey_t)commandInfoCopyValueForKey {
    return active;
}
@end

int main(void) {
    @autoreleasepool {
        TestCommand *other = [TestCommand new];
        other.identifier = 22;
        other.enabled = YES;
        other.active = @YES;
        TestCommand *like = [TestCommand new];
        like.identifier = 21;
        like.enabled = YES;
        like.active = @YES;
        NSDictionary * (^read)(NSArray *) = ^(NSArray *commands) {
          return feedbackStateForCommands(commands, commandID, enabled, active);
        };
        NSCAssert(([read(@[]) isEqual:@{
                      @"likeCommandEnabled" : @NO,
                      @"likeCommandActive" : @NO
                  }]),
                  @"missing command must disable support");
        NSCAssert(([read(@[ other ]) isEqual:@{
                      @"likeCommandEnabled" : @NO,
                      @"likeCommandActive" : @NO
                  }]),
                  @"dislike must not be mistaken for like");
        NSCAssert(([read(@[ other, like ]) isEqual:@{
                      @"likeCommandEnabled" : @YES,
                      @"likeCommandActive" : @YES
                  }]),
                  @"active like not found");
        like.active = @NO;
        NSCAssert(([read(@[ like ]) isEqual:@{
                      @"likeCommandEnabled" : @YES,
                      @"likeCommandActive" : @NO
                  }]),
                  @"unliked state lost");
        like.enabled = NO;
        like.active = @YES;
        NSCAssert(([read(@[ like ]) isEqual:@{
                      @"likeCommandEnabled" : @NO,
                      @"likeCommandActive" : @NO
                  }]),
                  @"disabled command retained active state");
        like.enabled = YES;
        like.active = nil;
        NSCAssert(([read(@[ like ]) isEqual:@{
                      @"likeCommandEnabled" : @YES,
                      @"likeCommandActive" : @NO
                  }]),
                  @"missing active state must not be true");
        like.active = @"invalid";
        NSCAssert(([read(@[ like ]) isEqual:@{
                      @"likeCommandEnabled" : @YES,
                      @"likeCommandActive" : @NO
                  }]),
                  @"malformed active state must not be true");
        like.active = @YES;
        NSDictionary *json = [NSJSONSerialization
            JSONObjectWithData:[NSJSONSerialization
                                   dataWithJSONObject:read(@[ like ])
                                              options:0
                                                error:nil]
                       options:0
                         error:nil];
        NSCAssert(
            CFGetTypeID((__bridge CFTypeRef)json[@"likeCommandEnabled"]) ==
                CFBooleanGetTypeID(),
            @"capability must serialize as a JSON boolean");
        NSCAssert(CFGetTypeID((__bridge CFTypeRef)json[@"likeCommandActive"]) ==
                      CFBooleanGetTypeID(),
                  @"active state must serialize as a JSON boolean");

        MediaRemote *original = g_mediaRemote;
        g_mediaRemote = [TestMediaRemote new];
        testCommands = @[ like ];
        for (NSNumber *unavailable in @[ @NO, @YES ]) {
            missingAPI = unavailable.boolValue;
            __block BOOL called = NO;
            requestFeedbackState(dispatch_get_main_queue(), ^(
                                     NSDictionary *state) {
              called = YES;
              NSCAssert(missingAPI ? state == nil
                                   : [state[@"likeCommandActive"] boolValue],
                        @"unexpected feedback state");
            });
            NSCAssert(called, @"feedback completion missing");
        }
        g_mediaRemote = original;
        puts("PASS: missing, unrelated, liked, unliked, disabled, "
             "missing-value, malformed-value, JSON booleans, "
             "available/unavailable API");
    }
    return 0;
}
