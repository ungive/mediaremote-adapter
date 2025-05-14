#ifndef MEDIAREMOTEADAPTER_DEBOUNCE
#define MEDIAREMOTEADAPTER_DEBOUNCE

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Debounce : NSObject

@property(nonatomic, assign, readonly) NSTimeInterval delay;
- (instancetype)initWithDelay:(NSTimeInterval)delay
                        queue:(nullable dispatch_queue_t)queue;
- (void)call:(dispatch_block_t)block;

@end

NS_ASSUME_NONNULL_END

#endif // MEDIAREMOTEADAPTER_DEBOUNCE
