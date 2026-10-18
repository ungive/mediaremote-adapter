#import <Foundation/Foundation.h>
#import "adapter/globals.h"
#import "MediaRemoteAdapter.h"

@interface Client : NSObject
@property NSString *bundleIdentifier;
@property NSString *parentApplicationBundleIdentifier;
@property NSDictionary *info;
@property unsigned int state;
@property int pid;
@end
@implementation Client
@end
static NSArray *sessions;
static void clients(dispatch_queue_t q, MRMediaRemoteGetNowPlayingClientsCompletion_t cb) { cb(sessions); }
static CFStringRef bundle(id c) { return (__bridge CFStringRef)[c bundleIdentifier]; }
static int pid(id c) { return [c pid]; }
static id origin(void) { return nil; }
static CFTypeRef path(id o,id c,id p) { return CFBridgingRetain(c); }
static void info(id p,void *u,dispatch_queue_t q,MRMediaRemoteGetNowPlayingInfoForPlayerCompletion_t cb) { cb([p info],nil); }
static void state(id p,dispatch_queue_t q,MRMediaRemoteGetPlaybackStateForPlayerCompletion_t cb) { cb([(Client *)p state]); }
@interface FakeMediaRemote : MediaRemote
@end
@implementation FakeMediaRemote
- (MRMediaRemoteGetNowPlayingClients_t)getNowPlayingClients { return clients; }
- (MRNowPlayingClientGetBundleIdentifier_t)nowPlayingClientGetBundleIdentifier { return bundle; }
- (MRNowPlayingClientGetProcessIdentifier_t)nowPlayingClientGetProcessIdentifier { return pid; }
- (MRMediaRemoteGetLocalOrigin_t)getLocalOrigin { return origin; }
- (MRNowPlayingPlayerPathCreate_t)nowPlayingPlayerPathCreate { return path; }
- (MRMediaRemoteGetNowPlayingInfoForPlayer_t)getNowPlayingInfoForPlayer { return info; }
- (MRMediaRemoteGetPlaybackStateForPlayer_t)getPlaybackStateForPlayer { return state; }
@end
int main() { @autoreleasepool {
 NSMutableArray *a=[NSMutableArray array];
 NSArray *input=[NSJSONSerialization JSONObjectWithData:[NSProcessInfo.processInfo.environment[@"SESSIONS"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
 for(NSDictionary *d in input){Client *c=[Client new]; c.bundleIdentifier=d[@"bundle"]; c.parentApplicationBundleIdentifier=[d[@"parent"] isKindOfClass:NSString.class] ? d[@"parent"] : nil; c.info=d[@"info"]; c.state=[d[@"state"] unsignedIntValue]; c.pid=[d[@"pid"] intValue]; [a addObject:c];}
 sessions=a; g_mediaRemote=[FakeMediaRemote new]; adapter_get();
} }
