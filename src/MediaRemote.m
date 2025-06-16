#include <Foundation/Foundation.h>
#import <dlfcn.h>

#include "MediaRemote.h"

#define MR_FRAMEWORK_PATH                                                      \
    "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

// Function names
CFStringRef MRMediaRemoteRegisterForNowPlayingNotifications =
    CFSTR("MRMediaRemoteRegisterForNowPlayingNotifications");
CFStringRef MRMediaRemoteUnregisterForNowPlayingNotifications =
    CFSTR("MRMediaRemoteUnregisterForNowPlayingNotifications");
CFStringRef MRMediaRemoteGetNowPlayingApplicationPID =
    CFSTR("MRMediaRemoteGetNowPlayingApplicationPID");
CFStringRef MRMediaRemoteGetNowPlayingInfo =
    CFSTR("MRMediaRemoteGetNowPlayingInfo");
CFStringRef MRMediaRemoteGetNowPlayingApplicationIsPlaying =
    CFSTR("MRMediaRemoteGetNowPlayingApplicationIsPlaying");
CFStringRef MRMediaRemoteSendCommand = CFSTR("MRMediaRemoteSendCommand");
CFStringRef MRMediaRemoteSetElapsedTime = CFSTR("MRMediaRemoteSetElapsedTime");

// Notification names
NSString *kMRMediaRemoteNowPlayingInfoDidChangeNotification =
    @"kMRMediaRemoteNowPlayingInfoDidChangeNotification";
NSString *kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification = @"kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification";
NSString *kMRMediaRemotePickableRoutesDidChangeNotification = @"kMRMediaRemotePickableRoutesDidChangeNotification";
NSString *kMRMediaRemoteNowPlayingApplicationDidChangeNotification = @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification";
NSString *kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification = @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification";

NSString *kMRMediaRemoteRouteStatusDidChangeNotification = @"kMRMediaRemoteRouteStatusDidChangeNotification";
NSString *kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey = @"kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey";
NSString *kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey = @"kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey";
NSString *kMRMediaRemoteNowPlayingInfoAlbum = @"kMRMediaRemoteNowPlayingInfoAlbum";
NSString *kMRMediaRemoteNowPlayingInfoArtist = @"kMRMediaRemoteNowPlayingInfoArtist";
NSString *kMRMediaRemoteNowPlayingInfoArtworkData = @"kMRMediaRemoteNowPlayingInfoArtworkData";
NSString *kMRMediaRemoteNowPlayingInfoArtworkMIMEType = @"kMRMediaRemoteNowPlayingInfoArtworkMIMEType";
NSString *kMRMediaRemoteNowPlayingInfoChapterNumber = @"kMRMediaRemoteNowPlayingInfoChapterNumber";
NSString *kMRMediaRemoteNowPlayingInfoComposer = @"kMRMediaRemoteNowPlayingInfoComposer";
NSString *kMRMediaRemoteNowPlayingInfoDuration = @"kMRMediaRemoteNowPlayingInfoDuration";
NSString *kMRMediaRemoteNowPlayingInfoElapsedTime = @"kMRMediaRemoteNowPlayingInfoElapsedTime";
NSString *kMRMediaRemoteNowPlayingInfoGenre = @"kMRMediaRemoteNowPlayingInfoGenre";
NSString *kMRMediaRemoteNowPlayingInfoIsAdvertisement = @"kMRMediaRemoteNowPlayingInfoIsAdvertisement";
NSString *kMRMediaRemoteNowPlayingInfoIsBanned = @"kMRMediaRemoteNowPlayingInfoIsBanned";
NSString *kMRMediaRemoteNowPlayingInfoIsInWishList = @"kMRMediaRemoteNowPlayingInfoIsInWishList";
NSString *kMRMediaRemoteNowPlayingInfoIsLiked = @"kMRMediaRemoteNowPlayingInfoIsLiked";
NSString *kMRMediaRemoteNowPlayingInfoIsMusicApp = @"kMRMediaRemoteNowPlayingInfoIsMusicApp";
NSString *kMRMediaRemoteNowPlayingInfoPlaybackRate = @"kMRMediaRemoteNowPlayingInfoPlaybackRate";
NSString *kMRMediaRemoteNowPlayingInfoProhibitsSkip = @"kMRMediaRemoteNowPlayingInfoProhibitsSkip";
NSString *kMRMediaRemoteNowPlayingInfoQueueIndex = @"kMRMediaRemoteNowPlayingInfoQueueIndex";
NSString *kMRMediaRemoteNowPlayingInfoRadioStationIdentifier = @"kMRMediaRemoteNowPlayingInfoRadioStationIdentifier";
NSString *kMRMediaRemoteNowPlayingInfoRepeatMode = @"kMRMediaRemoteNowPlayingInfoRepeatMode";
NSString *kMRMediaRemoteNowPlayingInfoShuffleMode = @"kMRMediaRemoteNowPlayingInfoShuffleMode";
NSString *kMRMediaRemoteNowPlayingInfoStartTime = @"kMRMediaRemoteNowPlayingInfoStartTime";
NSString *kMRMediaRemoteNowPlayingInfoSupportsFastForward15Seconds = @"kMRMediaRemoteNowPlayingInfoSupportsFastForward15Seconds";
NSString *kMRMediaRemoteNowPlayingInfoSupportsIsBanned = @"kMRMediaRemoteNowPlayingInfoSupportsIsBanned";
NSString *kMRMediaRemoteNowPlayingInfoSupportsIsLiked = @"kMRMediaRemoteNowPlayingInfoSupportsIsLiked";
NSString *kMRMediaRemoteNowPlayingInfoSupportsRewind15Seconds = @"kMRMediaRemoteNowPlayingInfoSupportsRewind15Seconds";
NSString *kMRMediaRemoteNowPlayingInfoTimestamp = @"kMRMediaRemoteNowPlayingInfoTimestamp";
NSString *kMRMediaRemoteNowPlayingInfoTitle = @"kMRMediaRemoteNowPlayingInfoTitle";
NSString *kMRMediaRemoteNowPlayingInfoTotalChapterCount = @"kMRMediaRemoteNowPlayingInfoTotalChapterCount";
NSString *kMRMediaRemoteNowPlayingInfoTotalDiscCount = @"kMRMediaRemoteNowPlayingInfoTotalDiscCount";
NSString *kMRMediaRemoteNowPlayingInfoTotalQueueCount = @"kMRMediaRemoteNowPlayingInfoTotalQueueCount";
NSString *kMRMediaRemoteNowPlayingInfoTotalTrackCount = @"kMRMediaRemoteNowPlayingInfoTotalTrackCount";
NSString *kMRMediaRemoteNowPlayingInfoTrackNumber = @"kMRMediaRemoteNowPlayingInfoTrackNumber";
NSString *kMRMediaRemoteNowPlayingInfoUniqueIdentifier = @"kMRMediaRemoteNowPlayingInfoUniqueIdentifier";
NSString *kMRMediaRemoteNowPlayingInfoRadioStationHash = @"kMRMediaRemoteNowPlayingInfoRadioStationHash";
NSString *kMRMediaRemoteOptionMediaType = @"kMRMediaRemoteOptionMediaType";
NSString *kMRMediaRemoteOptionSourceID = @"kMRMediaRemoteOptionSourceID";
NSString *kMRMediaRemoteOptionTrackID = @"kMRMediaRemoteOptionTrackID";
NSString *kMRMediaRemoteOptionStationID = @"kMRMediaRemoteOptionStationID";
NSString *kMRMediaRemoteOptionStationHash = @"kMRMediaRemoteOptionStationHash";
NSString *kMRMediaRemoteRouteDescriptionUserInfoKey = @"kMRMediaRemoteRouteDescriptionUserInfoKey";
NSString *kMRMediaRemoteRouteStatusUserInfoKey = @"kMRMediaRemoteRouteStatusUserInfoKey";

NSString *kMRNowPlayingClientUserInfoKey = @"kMRNowPlayingClientUserInfoKey";

static NSString *MediaRemoteFrameworkBundleURL = @"/System/Library/PrivateFrameworks/MediaRemote.framework";

@implementation MediaRemote

@synthesize registerForNowPlayingNotifications = _registerForNowPlayingNotifications;
@synthesize unregisterForNowPlayingNotifications = _unregisterForNowPlayingNotifications;
@synthesize getNowPlayingApplicationPID = _getNowPlayingApplicationPID;
@synthesize getNowPlayingInfo = _getNowPlayingInfo;
@synthesize getNowPlayingApplicationIsPlaying = _getNowPlayingApplicationIsPlaying;
@synthesize sendCommand = _sendCommand;
@synthesize setElapsedTime = _setElapsedTime;

- (id)init {
    self = [super init];
    if (self) {
        void *mediaRemoteFramework = dlopen(MR_FRAMEWORK_PATH, RTLD_LAZY);
        if (mediaRemoteFramework) {
            _registerForNowPlayingNotifications = dlsym(
                mediaRemoteFramework, "MRMediaRemoteRegisterForNowPlayingNotifications");
            _unregisterForNowPlayingNotifications = dlsym(
                mediaRemoteFramework, "MRMediaRemoteUnregisterForNowPlayingNotifications");
            _getNowPlayingApplicationPID = dlsym(
                mediaRemoteFramework, "MRMediaRemoteGetNowPlayingApplicationPID");
            _getNowPlayingInfo =
                dlsym(mediaRemoteFramework, "MRMediaRemoteGetNowPlayingInfo");
            _getNowPlayingApplicationIsPlaying = dlsym(
                mediaRemoteFramework, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
            _sendCommand = dlsym(mediaRemoteFramework, "MRMediaRemoteSendCommand");
            _setElapsedTime = dlsym(mediaRemoteFramework, "MRMediaRemoteSetElapsedTime");
        }
    }
    return self;
}
@end
