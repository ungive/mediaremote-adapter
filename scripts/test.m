#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Load the framework dynamically
        const char *frameworkPath = "/Users/macintosh/git/osascript-mediaremote/build/MediaRemoteAdapter.framework/MediaRemoteAdapter";
        void *handle = dlopen(frameworkPath, RTLD_NOW);
        if (!handle) {
            NSLog(@"Failed to load framework: %s", dlerror());
            return 1;
        }

        // Get the class reference
        Class MediaRemoteAdapterClass = objc_getClass("MediaRemoteAdapter");
        if (!MediaRemoteAdapterClass) {
            NSLog(@"Class not found.");
            return 1;
        }

        // Get the selector for the static method
        SEL selector = sel_registerName("loop");

        // Cast and call the class method
        ((void (*)(id, SEL))objc_msgSend)(MediaRemoteAdapterClass, selector);

        // Optionally unload the framework
        dlclose(handle);
    }
    return 0;
}

// clang -framework Foundation -o loadFrameworkExample load.m
