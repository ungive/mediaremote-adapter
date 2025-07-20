//
//  NowPlayingTest.h
//  mediaremote-adapter
//
//  Created by Alexander on 2024-07-19.
//

#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>

@class NowPlayingTest;

NS_ASSUME_NONNULL_BEGIN

// Protocol for remote command callbacks
@protocol NowPlayingRemoteCommandListener <NSObject>
- (void)didReceivePlayCommand;
- (void)didReceivePauseCommand;
@end

// Delegate to manage MPNowPlayingInfoCenter metadata
@interface NowPlayingInfoDelegate : NSObject
- (void)updateMetadataWithTitle:(NSString *)title artist:(NSString *)artist duration:(NSTimeInterval)duration;
- (void)setPlaybackRate:(float)rate elapsedTime:(NSTimeInterval)time;
@end

// Delegate to handle remote command callbacks
@interface NowPlayingRemoteCommandDelegate : NSObject
- (instancetype)initWithListener:(id<NowPlayingRemoteCommandListener>)listener;
@end

// Main test class that simulates a now playing client
@interface NowPlayingTest : NSObject
@end

// C-style functions for test setup and teardown
NowPlayingTest *TestSetupNowPlaying(void);
void TestCleanupNowPlaying(NowPlayingTest * _Nullable testInstance);

NS_ASSUME_NONNULL_END