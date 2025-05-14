#ifndef MEDIAREMOTEADAPTER_ADAPTER_H
#define MEDIAREMOTEADAPTER_ADAPTER_H

#import <Foundation/Foundation.h>

@interface MediaRemoteAdapter : NSObject

+ (void)loop;
+ (void)stop;

@end

extern NSString *kTitle;
extern NSString *kArtist;
extern NSString *kAlbum;
extern NSString *kDuration;
extern NSString *kElapsedTime;
extern NSString *kTimestampEpochMicro;
extern NSString *kArtworkMimeType;
extern NSString *kArtworkDataBase64;

#endif // MEDIAREMOTEADAPTER_ADAPTER_H
