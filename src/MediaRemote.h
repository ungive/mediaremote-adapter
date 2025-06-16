#ifndef MEDIAREMOTE_PRIVATE_H_
#define MEDIAREMOTE_PRIVATE_H_

#include <Foundation/Foundation.h>

#pragma mark - Notifications

extern NSString *kMRMediaRemoteNowPlayingInfoDidChangeNotification;
extern NSString *kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification;

#pragma mark - Keys

extern NSString *kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey;
extern NSString *kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey;
extern NSString *kMRMediaRemoteNowPlayingInfoTitle;
extern NSString *kMRMediaRemoteNowPlayingInfoArtist;
extern NSString *kMRMediaRemoteNowPlayingInfoAlbum;
extern NSString *kMRMediaRemoteNowPlayingInfoGenre;
extern NSString *kMRMediaRemoteNowPlayingInfoDuration;
extern NSString *kMRMediaRemoteNowPlayingInfoElapsedTime;
extern NSString *kMRMediaRemoteNowPlayingInfoArtworkData;
extern NSString *kMRMediaRemoteNowPlayingInfoArtworkMIMEType;
extern NSString *kMRMediaRemoteNowPlayingInfoTimestamp;

#pragma mark - API Function Names

extern CFStringRef MRMediaRemoteRegisterForNowPlayingNotifications;
extern CFStringRef MRMediaRemoteUnregisterForNowPlayingNotifications;
extern CFStringRef MRMediaRemoteGetNowPlayingApplicationPID;
extern CFStringRef MRMediaRemoteGetNowPlayingInfo;
extern CFStringRef MRMediaRemoteGetNowPlayingApplicationIsPlaying;
extern CFStringRef MRMediaRemoteSendCommand;
extern CFStringRef MRMediaRemoteSetElapsedTime;

#pragma mark - API Types

// Callbacks
typedef void (^MRMediaRemoteGetNowPlayingInfoCompletion_t)(NSDictionary *information);
typedef void (^MRMediaRemoteGetNowPlayingApplicationPIDCompletion_t)(int PID);
typedef void (^MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion_t)(bool isPlaying);

// Function Signatures
typedef void (*MRMediaRemoteRegisterForNowPlayingNotifications_t)(dispatch_queue_t queue);
typedef void (*MRMediaRemoteUnregisterForNowPlayingNotifications_t)();
typedef void (*MRMediaRemoteGetNowPlayingApplicationPID_t)(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationPIDCompletion_t completion);
typedef void (*MRMediaRemoteGetNowPlayingInfo_t)(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingInfoCompletion_t completion);
typedef void (*MRMediaRemoteGetNowPlayingApplicationIsPlaying_t)(dispatch_queue_t queue, MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion_t completion);

// Command Types
typedef enum {
    kMRTogglePlayPause = 1,
    kMRPlay = 4,
    kMRPause = 5,
    kMRStop = 6,
    kMRNextTrack = 8,
    kMRPreviousTrack = 9,
} MRMediaRemoteCommand;

typedef void (*MRMediaRemoteSendCommand_t)(MRMediaRemoteCommand command, id options);
typedef void (*MRMediaRemoteSetElapsedTime_t)(double elapsedTime);

#pragma mark - Main Interface

@interface MediaRemote : NSObject
// Observers
@property(readonly) MRMediaRemoteRegisterForNowPlayingNotifications_t registerForNowPlayingNotifications;
@property(readonly) MRMediaRemoteUnregisterForNowPlayingNotifications_t unregisterForNowPlayingNotifications;
// Metadata
@property(readonly) MRMediaRemoteGetNowPlayingApplicationPID_t getNowPlayingApplicationPID;
@property(readonly) MRMediaRemoteGetNowPlayingInfo_t getNowPlayingInfo;
@property(readonly) MRMediaRemoteGetNowPlayingApplicationIsPlaying_t getNowPlayingApplicationIsPlaying;
// Commands
@property(readonly) MRMediaRemoteSendCommand_t sendCommand;
@property(readonly) MRMediaRemoteSetElapsedTime_t setElapsedTime;
// Constructor
-(id)init;
@end

#endif /* MEDIAREMOTE_PRIVATE_H_ */