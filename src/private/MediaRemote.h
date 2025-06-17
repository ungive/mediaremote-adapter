// clang-format off

#ifndef MEDIAREMOTE_PRIVATE_H_
#define MEDIAREMOTE_PRIVATE_H_

#include <Foundation/Foundation.h>

#pragma mark Notifications

extern NSString *kMRMediaRemoteNowPlayingInfoDidChangeNotification;
extern NSString *kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification;
extern NSString *kMRMediaRemotePickableRoutesDidChangeNotification;
extern NSString *kMRMediaRemoteNowPlayingApplicationDidChangeNotification;
extern NSString *kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification;
extern NSString *kMRMediaRemoteRouteStatusDidChangeNotification;

#pragma mark Keys

extern NSString *kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey;
extern NSString *kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey;
extern NSString *kMRMediaRemoteNowPlayingInfoAlbum;
extern NSString *kMRMediaRemoteNowPlayingInfoArtist;
extern NSString *kMRMediaRemoteNowPlayingInfoArtworkData;
extern NSString *kMRMediaRemoteNowPlayingInfoArtworkMIMEType;
extern NSString *kMRMediaRemoteNowPlayingInfoChapterNumber;
extern NSString *kMRMediaRemoteNowPlayingInfoComposer;
extern NSString *kMRMediaRemoteNowPlayingInfoDuration;
extern NSString *kMRMediaRemoteNowPlayingInfoElapsedTime;
extern NSString *kMRMediaRemoteNowPlayingInfoGenre;
extern NSString *kMRMediaRemoteNowPlayingInfoIsAdvertisement;
extern NSString *kMRMediaRemoteNowPlayingInfoIsBanned;
extern NSString *kMRMediaRemoteNowPlayingInfoIsInWishList;
extern NSString *kMRMediaRemoteNowPlayingInfoIsLiked;
extern NSString *kMRMediaRemoteNowPlayingInfoIsMusicApp;
extern NSString *kMRMediaRemoteNowPlayingInfoPlaybackRate;
extern NSString *kMRMediaRemoteNowPlayingInfoProhibitsSkip;
extern NSString *kMRMediaRemoteNowPlayingInfoQueueIndex;
extern NSString *kMRMediaRemoteNowPlayingInfoRadioStationIdentifier;
extern NSString *kMRMediaRemoteNowPlayingInfoRepeatMode;
extern NSString *kMRMediaRemoteNowPlayingInfoShuffleMode;
extern NSString *kMRMediaRemoteNowPlayingInfoStartTime;
extern NSString *kMRMediaRemoteNowPlayingInfoSupportsFastForward15Seconds;
extern NSString *kMRMediaRemoteNowPlayingInfoSupportsIsBanned;
extern NSString *kMRMediaRemoteNowPlayingInfoSupportsIsLiked;
extern NSString *kMRMediaRemoteNowPlayingInfoSupportsRewind15Seconds;
extern NSString *kMRMediaRemoteNowPlayingInfoTimestamp;
extern NSString *kMRMediaRemoteNowPlayingInfoTitle;
extern NSString *kMRMediaRemoteNowPlayingInfoTotalChapterCount;
extern NSString *kMRMediaRemoteNowPlayingInfoTotalDiscCount;
extern NSString *kMRMediaRemoteNowPlayingInfoTotalQueueCount;
extern NSString *kMRMediaRemoteNowPlayingInfoTotalTrackCount;
extern NSString *kMRMediaRemoteNowPlayingInfoTrackNumber;
extern NSString *kMRMediaRemoteNowPlayingInfoUniqueIdentifier;
extern NSString *kMRMediaRemoteNowPlayingInfoRadioStationHash;
extern NSString *kMRMediaRemoteOptionMediaType;
extern NSString *kMRMediaRemoteOptionSourceID;
extern NSString *kMRMediaRemoteOptionTrackID;
extern NSString *kMRMediaRemoteOptionStationID;
extern NSString *kMRMediaRemoteOptionStationHash;
extern NSString *kMRMediaRemoteRouteDescriptionUserInfoKey;
extern NSString *kMRMediaRemoteRouteStatusUserInfoKey;

#pragma mark API

extern CFStringRef MRMediaRemoteRegisterForNowPlayingNotifications;
extern CFStringRef MRMediaRemoteUnregisterForNowPlayingNotifications;
extern CFStringRef MRMediaRemoteGetNowPlayingApplicationPID;
extern CFStringRef MRMediaRemoteGetNowPlayingInfo;
extern CFStringRef MRMediaRemoteGetNowPlayingApplicationIsPlaying;

typedef void (*MRMediaRemoteRegisterForNowPlayingNotifications_t)(dispatch_queue_t queue);
typedef void (*MRMediaRemoteUnregisterForNowPlayingNotifications_t)();

typedef void (^MRMediaRemoteGetNowPlayingInfoCompletion_t)(NSDictionary *information);
typedef void (^MRMediaRemoteGetNowPlayingApplicationPIDCompletion_t)(int PID);
typedef void (^MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion_t)(bool isPlaying);

typedef void (*MRMediaRemoteGetNowPlayingApplicationPID_t)(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationPIDCompletion_t completion);
typedef void (*MRMediaRemoteGetNowPlayingInfo_t)(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingInfoCompletion_t completion);
typedef void (*MRMediaRemoteGetNowPlayingApplicationIsPlaying_t)(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion_t completion);

#pragma mark Miscellaneous

extern NSString *kMRNowPlayingClientUserInfoKey;

// Accessed with the kMRNowPlayingClientUserInfoKey
// on the userInfo dictionary of an NSNotification.
@interface MRClient : NSObject {}
-(NSString *)parentApplicationBundleIdentifier;
-(NSString *)bundleIdentifier;
-(NSString *)displayName;
@end

@interface MediaRemote : NSObject
// Observers
@property(readonly) MRMediaRemoteRegisterForNowPlayingNotifications_t registerForNowPlayingNotifications;
@property(readonly) MRMediaRemoteUnregisterForNowPlayingNotifications_t unregisterForNowPlayingNotifications;
// Metadata
@property(readonly) MRMediaRemoteGetNowPlayingApplicationPID_t getNowPlayingApplicationPID;
@property(readonly) MRMediaRemoteGetNowPlayingInfo_t getNowPlayingInfo;
@property(readonly) MRMediaRemoteGetNowPlayingApplicationIsPlaying_t getNowPlayingApplicationIsPlaying;
// Constructor
-(id)init;
@end

#endif /* MEDIAREMOTE_PRIVATE_H_ */
