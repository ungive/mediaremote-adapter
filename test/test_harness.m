//
//  main.m
//  TestHarness
//
//  Created by Gemini on 6/13/25.
//

#import <Foundation/Foundation.h>
#import "MediaRemoteAdapter.h"

// C callback function to handle incoming data
void handle_media_data(const char* json_string) {
    NSString *jsonString = [NSString stringWithUTF8String:json_string];
    printf("%s\n", [jsonString UTF8String]);
    fflush(stdout);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        fprintf(stderr, "TestHarness: Registering callback and starting media loop...\n");

        // Register the callback function
        register_media_data_callback(handle_media_data);

        // Start the media observer loop
        loop();

        // Keep the application running to receive updates.
        // The loop() function runs on a background thread, so the main thread
        // must be kept alive.
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
} 