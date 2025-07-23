// Copyright (c) 2025 Alexander5015
// This file is licensed under the BSD 3-Clause License.

#import <Foundation/Foundation.h>
#import "NowPlayingTest.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Redirect stderr to stdout so NSLog and fprintf(stderr, ...) are visible to parent
        dup2(STDOUT_FILENO, STDERR_FILENO);

        NowPlayingPublishTest *test = [[NowPlayingPublishTest alloc] init];
        NSLog(@"NowPlayingTestHelper: setup_done");
        printf("setup_done\n");
        fflush(stdout);

        // Wait for cleanup command, but keep listener responsive
        BOOL shouldExit = NO;
        while (!shouldExit) {
            // Wait up to 0.2s for input, but always spin the runloop for responsiveness
            NSDate *waitUntil = [NSDate dateWithTimeIntervalSinceNow:0.2];
            while ([[NSDate date] compare:waitUntil] == NSOrderedAscending) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:waitUntil];
            }
            // Check if there's input available
            fd_set fds;
            struct timeval tv = {0, 0};
            FD_ZERO(&fds);
            FD_SET(STDIN_FILENO, &fds);
            int ret = select(STDIN_FILENO + 1, &fds, NULL, NULL, &tv);
            if (ret > 0 && FD_ISSET(STDIN_FILENO, &fds)) {
                char buf[256];
                if (fgets(buf, sizeof(buf), stdin)) {
                    NSString *command = [[NSString alloc] initWithUTF8String:buf];
                    command = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if ([command isEqualToString:@"cleanup"]) {
                        NSLog(@"NowPlayingTestHelper: cleanup_done");
                        printf("cleanup_done\n");
                        fflush(stdout);
                        shouldExit = YES;
                        break;
                    } else if ([command length] == 0) {
                        continue;
                    } else {
                        NSLog(@"NowPlayingTestHelper: Unknown command: %@", command);
                        printf("unknown_command\n");
                        fflush(stdout);
                    }
                }
            }
        }
    }
    return 0;
}
