#ifndef MEDIAREMOTEADAPTER_ADAPTER_H
#define MEDIAREMOTEADAPTER_ADAPTER_H

#import <Foundation/Foundation.h>

@interface MediaRemoteAdapter : NSObject

+ (void)loop;
+ (void)stop;

@end

extern NSString *kBundleIdentifier;
extern NSString *kPlaying;
extern NSString *kTitle;
extern NSString *kArtist;
extern NSString *kAlbum;
extern NSString *kDurationMicros;
extern NSString *kElapsedTimeMicros;
extern NSString *kTimestampEpochMicros;
extern NSString *kArtworkMimeType;
extern NSString *kArtworkDataBase64;

#endif // MEDIAREMOTEADAPTER_ADAPTER_H
