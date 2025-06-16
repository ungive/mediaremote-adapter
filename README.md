> **@Apple**&ensp;*Before breaking this,
> please consider giving Mac users the option
> to share actively playing media with the apps they use
> and to control media playback.
> Perhaps by introducing a new entitlement
> that can be granted to apps by users in the system settings.
> There are
> [many](https://musicpresence.app)
> [use](https://folivora.ai)
> [cases](https://lyricfever.com)
> [for](https://theboring.name)
> [this](https://github.com/kirtan-shah/nowplaying-cli).*

> **@Developers**&ensp;*Please **star**
> this repository to show Apple that we care.*

---

<!-- BADGES BEGIN -->
![](https://img.shields.io/static/v1?label=macOS&message=macOS%2026.0%20%2825A5279m%29&labelColor=444&color=blue)
![](https://img.shields.io/static/v1?label=last%20tested&message=Mon%20Jun%2016%2016%3A43%3A24%20CEST%202025&labelColor=444&color)
<!-- BADGES END -->

# MediaRemote Adapter

Get now playing information using the MediaRemote framework
on all macOS versions, including 15.4 and above.

This works by using a system binary &ndash; `/usr/bin/perl` in this case &ndash;
which is entitled to use the MediaRemote framework
and by dynamically loading a custom helper framework
that prints real-time updates to stdout.

## Features

- Minimal and simple C API:
  - `loop()`: Starts monitoring for media changes on a background thread.
  - `stop_media_remote_loop()`: Stops the monitoring loop.
  - `register_media_data_callback()`: Registers a C function pointer to receive data.
- Real-time updates delivered via a callback with a JSON payload.
- Full metadata support for now playing items, including artwork.
- Pure Objective-C, no external dependencies.
- Extensibility to support more MediaRemote features in the future (contributions welcome).
- Optional debounce delay to prevent bursts of small updates (the default is 100ms).

## Building

A helper script is provided to automate the build process.

```bash
# Build the framework (default action)
./build.sh

# Clean the build directory
./build.sh clean
```

The compiled `MediaRemoteAdapter.framework` will be located in the `build/src/` directory.

## Usage

1.  Link `MediaRemoteAdapter.framework` in your application.
2.  Import the public header: `#import <MediaRemoteAdapter/MediaRemoteAdapter.h>`
3.  Implement a callback function to receive the data.
4.  Register your callback and start the loop.

The data is delivered as a C-string containing a JSON dictionary with the following keys:

- `type` (string): Always `"data"`.
- `diff` (boolean): If `true`, the `payload` only contains keys for values that have changed since the last full payload.
- `payload` (dictionary): The now playing metadata. For a list of all possible keys, see `src/MediaRemoteAdapterKeys.m`.

### Example (Objective-C)

```objective-c
#import <Foundation/Foundation.h>
#import <MediaRemoteAdapter/MediaRemoteAdapter.h>

// C callback function to handle incoming data
void handle_media_data(const char* json_string) {
    NSString *jsonString = [NSString stringWithUTF8String:json_string];
    NSLog(@"Received data: %@", jsonString);
    
    // It is recommended to use NSJSONSerialization to parse the data
    // NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    // NSError *error = nil;
    // NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"Registering callback and starting media loop...");

        // Register the callback function
        register_media_data_callback(handle_media_data);

        // Start the media observer loop
        loop();

        // Keep the application running to receive updates
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
```

## Why this works

According to the findings by [@My-Iris](https://github.com/Mx-Iris) in
[this comment](https://github.com/aviwad/LyricFever/issues/94#issuecomment-2746155419)
a process must have a bundle identifier starting with `com.apple.` to be granted permission to access the MediaRemote framework.

This framework does **not** solve that problem on its own. It is a library that must be loaded and used by a host process that possesses the required entitlement (e.g., by running a script with `/usr/bin/perl`, which has the `com.apple.perl` identifier).

You can confirm this by streaming log messages using the Console.app
whilst running your entitled host process:

`default	14:44:55.871495+0200	mediaremoted	Adding client <MRDMediaRemoteClient 0x15820b1a0, bundleIdentifier = com.apple.perl5, pid = 86889>`

## Projects that use this library

- [Music Presence](https://musicpresence.app) is a cross-platform desktop application
  for showing what you are listening to in your Discord status.
  It uses this library since version [2.3.1](https://github.com/ungive/discord-music-presence/releases/tag/v2.3.1)
  to detect media from all media players again.

## Motivation

This project was created due to the MediaRemote framework
being completely non-functional when being loaded directly from within an app,
starting with macOS 15.4 (see the numerous issues linked below).

The aim of this project is to provide a tool (and perhaps soon a full library)
that serves as a fully functional alternative to using MediaRemote directly
and perhaps to inspire Apple to give us a public API
to read now playing information and control media playback on the device
(see the note at the top of this file).

## Contributing

This project aims to be a universal drop-in replacement
for directly using the MediaRemote framework on Mac.

If you have the time to contribute, you are more than welcome to do so,
any help to improve this project is greatly appreciated!
You can find things to work on in the list of TODOs below,
in open issues and in the TODO and FIXME comments
in the project's source files.

I do not primarily develop for Mac,
so if you see any bad practices in my Objective-C code,
please do not hesitate to point them out.

## Useful links

- Issues regarding MediaRemote breaking since macOS 15.4
  - https://github.com/vincentneo/LosslessSwitcher/issues/161
  - https://github.com/aviwad/LyricFever/issues/94
  - https://github.com/TheBoredTeam/boring.notch/issues/417
  - https://community.folivora.ai/t/now-playing-is-no-longer-working-on-macos-15-4/42802/11
  - https://github.com/ungive/discord-music-presence/issues/165
  - https://github.com/ungive/discord-music-presence/issues/245
  - https://github.com/kirtan-shah/nowplaying-cli/issues/28
- Getting now playing information using `osascript` and `MRNowPlayingRequest`.
  Note that this is unable to load the song artwork
  and it is impossible to get real-time updates with this solution.
  It is much simpler to implement though
  - https://github.com/EinTim23/PlayerLink/commit/9821b6a294873f975852f06419a0baf2fe404800
  - https://github.com/fastfetch-cli/fastfetch/commit/1557f0c5564a8288604824e55db47508f65e82c9
  - https://gist.github.com/SKaplanOfficial/f9f5bdd6455436203d0d318c078358de

## Acknowledgements

Thank you [@EinTim23](https://github.com/EinTim23) for bringing
a [similar workaround](https://github.com/EinTim23/PlayerLink/commit/9821b6a294873f975852f06419a0baf2fe404800) to my attention!
Without your hint I most likely would not have dug into this anytime soon
and my app [Music Presence](https://musicpresence.app)
would still only work with AppleScript automation.

Thank you [@My-Iris](https://github.com/Mx-Iris)
for providing insight into the changes made since macOS 15.4:
[aviwad/LyricFever#94](https://github.com/aviwad/LyricFever/issues/94#issuecomment-2746155419)

## License

This file is licensed under the BSD 3-Clause License.
See [LICENSE](./LICENSE) for details.

Copyright (c) 2025 Jonas van den Berg
