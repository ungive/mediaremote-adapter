// Copyright (c) 2026 barissglc
// This file is licensed under the BSD 3-Clause License.

#import <Foundation/Foundation.h>
#import "adapter/feedback.h"
#import "adapter/globals.h"

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
    NSCAssert(CFEqual(key, CFSTR("kMRMediaRemoteCommandInfoIsActiveKey")), @"wrong state key");
    return CFBridgingRetain(((TestCommand *)command).active);
}

static int beforePID, afterPID, pidReads;
static BOOL missingAPI;
static NSArray *testCommands;
static void readPID(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationPIDCompletion_t completion) {
    (void)queue;
    completion(pidReads++ == 0 ? beforePID : afterPID);
}
static void readCommands(dispatch_queue_t queue, void (^completion)(NSArray *)) {
    (void)queue;
    completion(testCommands);
}

@interface TestMediaRemote : MediaRemote
@end
@implementation TestMediaRemote
- (MRMediaRemoteGetNowPlayingApplicationPID_t)getNowPlayingApplicationPID { return readPID; }
- (MRMediaRemoteCopySupportedCommands_t)copySupportedCommands { return missingAPI ? NULL : readCommands; }
- (MRMediaRemoteCommandInfoGetCommand_t)commandInfoGetCommand { return commandID; }
- (MRMediaRemoteCommandInfoGetEnabled_t)commandInfoGetEnabled { return enabled; }
- (MRMediaRemoteCommandInfoCopyValueForKey_t)commandInfoCopyValueForKey { return active; }
@end

int main(void) {
    @autoreleasepool {
        TestCommand *other = [TestCommand new];
        other.identifier = 22; other.enabled = YES; other.active = @YES;
        TestCommand *like = [TestCommand new];
        like.identifier = 21; like.enabled = YES; like.active = @YES;
        NSDictionary *(^read)(NSArray *) = ^(NSArray *commands) {
          return feedbackStateForCommands(commands, commandID, enabled, active);
        };
        NSCAssert(([read(@[]) isEqual:@{@"supportsIsLiked":@NO, @"isLiked":@NO}]), @"missing command must disable support");
        NSCAssert(([read(@[other]) isEqual:@{@"supportsIsLiked":@NO, @"isLiked":@NO}]), @"dislike must not be mistaken for like");
        NSCAssert(([read(@[other, like]) isEqual:@{@"supportsIsLiked":@YES, @"isLiked":@YES}]), @"active like not found");
        like.active = @NO;
        NSCAssert(([read(@[like]) isEqual:@{@"supportsIsLiked":@YES, @"isLiked":@NO}]), @"unliked state lost");
        like.enabled = NO; like.active = @YES;
        NSCAssert(([read(@[like]) isEqual:@{@"supportsIsLiked":@NO, @"isLiked":@NO}]), @"disabled command retained active state");
        like.enabled = YES; like.active = nil;
        NSCAssert(([read(@[like]) isEqual:@{@"supportsIsLiked":@YES, @"isLiked":@NO}]), @"missing active state must not be true");
        like.active = @"invalid";
        NSCAssert(([read(@[like]) isEqual:@{@"supportsIsLiked":@YES, @"isLiked":@NO}]), @"malformed active state must not be true");
        like.active = @YES;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:read(@[like]) options:0 error:nil] options:0 error:nil];
        NSCAssert(CFGetTypeID((__bridge CFTypeRef)json[@"supportsIsLiked"]) == CFBooleanGetTypeID(), @"capability must serialize as a JSON boolean");
        NSCAssert(CFGetTypeID((__bridge CFTypeRef)json[@"isLiked"]) == CFBooleanGetTypeID(), @"active state must serialize as a JSON boolean");

        NSMutableDictionary *metadata = [@{@"supportsIsLiked":@YES, @"isLiked":@YES} mutableCopy];
        addMissingFeedbackState(metadata, @{@"supportsIsLiked":@NO, @"isLiked":@NO});
        NSCAssert(([metadata isEqual:@{@"supportsIsLiked":@YES, @"isLiked":@YES}]), @"existing player metadata must take precedence");
        [metadata removeObjectForKey:@"isLiked"];
        addMissingFeedbackState(metadata, @{@"supportsIsLiked":@NO, @"isLiked":@NO});
        NSCAssert(([metadata isEqual:@{@"supportsIsLiked":@YES, @"isLiked":@NO}]), @"missing fields must be filled individually");

        MediaRemote *original = g_mediaRemote;
        g_mediaRemote = [TestMediaRemote new];
        testCommands = @[like];
        for (NSNumber *changed in @[@NO, @YES]) {
            beforePID = 123; afterPID = changed.boolValue ? 456 : 123; pidReads = 0;
            __block BOOL called = NO;
            requestFeedbackState(dispatch_get_main_queue(), ^(NSDictionary *state, int pid) {
                called = YES;
                NSCAssert(pid == afterPID, @"wrong owner PID");
                NSCAssert(changed.boolValue ? state == nil : [state[@"isLiked"] boolValue], @"state from a changed owner must be discarded");
            });
            NSCAssert(called, @"completion missing");
        }
        for (NSNumber *unavailable in @[@NO, @YES]) {
            missingAPI = unavailable.boolValue;
            beforePID = 0; pidReads = 0;
            __block BOOL called = NO;
            requestFeedbackState(dispatch_get_main_queue(), ^(NSDictionary *state, int pid) {
                called = YES;
                NSCAssert(state == nil && pid == 0, @"unavailable feedback must preserve the existing metadata path");
            });
            NSCAssert(called, @"unavailable feedback completion missing");
        }
        g_mediaRemote = original;
        puts("PASS: missing, unrelated, liked, unliked, disabled, missing-value, malformed-value, JSON booleans, stable/changed/no owner, unavailable API");
    }
    return 0;
}
