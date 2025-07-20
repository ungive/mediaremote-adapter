//
//  NowPlayingTest.m
//  mediaremote-adapter
//
//  Created by Alexander on 2024-07-19.
//

#import "NowPlayingTest.h"

@implementation NowPlayingInfoDelegate

- (void)updateMetadataWithTitle:(nonnull NSString *)title artist:(nonnull NSString *)artist duration:(NSTimeInterval)duration {
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = @{
        MPMediaItemPropertyTitle: title,
        MPMediaItemPropertyArtist: artist,
        MPMediaItemPropertyPlaybackDuration: @(duration),
        MPNowPlayingInfoPropertyElapsedPlaybackTime: @0,
        MPNowPlayingInfoPropertyPlaybackRate: @1,
        MPNowPlayingInfoPropertyMediaType: @(MPNowPlayingInfoMediaTypeAudio)
    };
}

- (void)setPlaybackRate:(float)rate elapsedTime:(NSTimeInterval)time {
    NSMutableDictionary *info = [MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo mutableCopy];
    if (!info) return;
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(rate);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(time);
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
}

@end

@implementation NowPlayingRemoteCommandDelegate {
    __weak id<NowPlayingRemoteCommandListener> _listener;
}

- (instancetype)initWithListener:(nonnull id<NowPlayingRemoteCommandListener>)listener {
    if (self = [super init]) {
        _listener = listener;
        MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;

        [center.playCommand addTarget:self action:@selector(onPlay:)];
        center.playCommand.enabled = YES;

        [center.pauseCommand addTarget:self action:@selector(onPause:)];
        center.pauseCommand.enabled = YES;
    }
    return self;
}

- (void)dealloc {
    MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
    [center.playCommand removeTarget:self];
    [center.pauseCommand removeTarget:self];
}

- (MPRemoteCommandHandlerStatus)onPlay:(nonnull MPRemoteCommandEvent *)event {
    [_listener didReceivePlayCommand];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)onPause:(nonnull MPRemoteCommandEvent *)event {
    [_listener didReceivePauseCommand];
    return MPRemoteCommandHandlerStatusSuccess;
}

@end

// Class extension to conform to the listener protocol privately
@interface NowPlayingTest() <NowPlayingRemoteCommandListener>
@end

@implementation NowPlayingTest {
    NowPlayingInfoDelegate *_infoDelegate;
    NowPlayingRemoteCommandDelegate *_remoteCommandDelegate;
    BOOL _isPlaying;
    NSTimeInterval _elapsedTime;
    NSDate *_playbackStartDate;
    NSTimeInterval _totalDuration;
}

- (instancetype)init {
    if (self = [super init]) {
        _infoDelegate = [NowPlayingInfoDelegate new];
        _remoteCommandDelegate = [[NowPlayingRemoteCommandDelegate alloc] initWithListener:self];

        _totalDuration = 60*10; // 10 minutes
        _elapsedTime = 0;
        _isPlaying = YES;
        _playbackStartDate = [NSDate date];

        [_infoDelegate updateMetadataWithTitle:@"Lost Cause" artist:@"ungive" duration:_totalDuration];
        [self updateNowPlayingInfo];
    }
    return self;
}

- (void)didReceivePlayCommand {
    if (!_isPlaying) {
        _isPlaying = YES;
        _playbackStartDate = [NSDate date];
        [self updateNowPlayingInfo];
    }
}

- (void)didReceivePauseCommand {
    if (_isPlaying) {
        _isPlaying = NO;
        if (_playbackStartDate) {
            _elapsedTime += [[NSDate date] timeIntervalSinceDate:_playbackStartDate];
            if (_elapsedTime > _totalDuration) _elapsedTime = _totalDuration;
        }
        _playbackStartDate = nil;
        [self updateNowPlayingInfo];
    }
}

- (void)updateNowPlayingInfo {
    NSTimeInterval currentElapsed = _elapsedTime;
    float playbackRate = 0.0f;

    if (_isPlaying) {
        if (_playbackStartDate) {
            currentElapsed += [[NSDate date] timeIntervalSinceDate:_playbackStartDate];
        }

        if (currentElapsed >= _totalDuration) {
            currentElapsed = _totalDuration;
            playbackRate = 0.0f;
            _isPlaying = NO;
        } else {
            playbackRate = 1.0f;
        }
    }

    [_infoDelegate setPlaybackRate:playbackRate elapsedTime:currentElapsed];
}

@end

NowPlayingTest *TestSetupNowPlaying(void) {
    return [NowPlayingTest new];
}

void TestCleanupNowPlaying(NowPlayingTest *testInstance) {
    // Setting the strong reference to nil will trigger ARC to release the object
    testInstance = nil;

    // Also clear the now playing info from the control center to leave a clean state.
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = nil;
}
