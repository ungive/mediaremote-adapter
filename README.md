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
![](https://img.shields.io/github/stars/ungive/mediaremote-adapter?style=flat&label=stars&logo=github&labelColor=444&color=DAAA3F&cacheSeconds=3600)
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

## Try it now

```sh
$ brew tap ungive/media-control
$ brew install media-control
$ media-control get                # Get now playing information once
$ media-control stream             # Stream now playing updates in real-time
$ media-control toggle-play-pause  # Toggle playback
$ media-control                    # Print help
```

For advanced usage examples,
read the CLI documentation:
[github.com/ungive/media-control](https://github.com/ungive/media-control)

## Features

- Minimal and simple API:
  - Bundle the MediaRemoteAdapter.framework with your app
  - Execute the provided perl script using e.g. `NSTask`
  - Then consume simple JSON and base64 encoded data
    that is streamed to the standard output.
    You can use `NSJSONSerialization` and `NSData`'s
    `initWithBase64EncodedString` for decoding
- Full metadata support for now playing items
- Real-time updates to changes of now playing information
- Pure Objective-C and Perl (shipped with macOS), no external dependencies
- Extensibility to support more MediaRemote features in the future
  (contributions welcome)
- Optional debounce delay to prevent bursts of small updates
  (the default is 100ms)

## Build from source

```
$ git clone https://github.com/ungive/mediaremote-adapter.git
$ cd mediaremote-adapter
$ mkdir build && cd build
$ cmake ..
$ cmake --build .
$ cd ..
$ FRAMEWORK_PATH=$(realpath ./build/MediaRemoteAdapter.framework)
$ /usr/bin/perl ./bin/mediaremote-adapter.pl "$FRAMEWORK_PATH"
```

The output of this command is characterised by the following rules:

- The script runs indefinitely until the process is terminated with a signal
- Each line printed to stdout contains a single JSON dictionary with the following keys:
    - `type` (string): Always "data". There are no other types at the moment
    - `diff` (boolean): Whether to update the previous non-diff payload. When this value is true, only the keys for updated values are set in the payload. Other keys should retain the value of the data payloads before this one
    - `payload` (dictionary): The now playing metadata. The keys should be self-explanatory. For details check the `convertNowPlayingInformation` function in [src/adapter/stream.m](./src/adapter/stream.m). All available keys are always set to either a value or null when diff is false or no keys are set at all when no media player is reporting now playing information. There are may be missing keys when diff is true, but at least one keys is always set. For a list of all keys check [src/adapter/stream_payload_keys.h](./src/adapter/stream_payload_keys.h)
- The script exits with an exit code other than 0 when a fatal error occured, e.g. when the MediaRemote framework could not be loaded. This may be used to stop any retries of executing this command again
- The script terminates gracefully when a `SIGTERM` signal is sent to the process. This signal should be used to cancel the observation of changes to now playing items
- It is recommended to use Objective-C's `NSJSONSerialization` for deserialization of JSON output, since that is used to serialize the underlying `NSDictionary`. Escape sequences like `\/` may not be parsed properly otherwise. Likewise, `NSData`'s `initWithBase64EncodedString` method may be used to parse the base64-encoded artwork data
- You must always pass the full path of the adapter framework to the script as the first argument
- The second optional argument is the function to execute (`loop` by default)
- Each line printed to stderr is an error message

Here is an example of what the output may look like:

```
{"type":"data","diff":false,"payload":{"artist":"Sara Rikas","timestampEpochMicros":1747256447190675,"title":"Cigarety","bundleIdentifier":"com.tidal.desktop","elapsedTimeMicros":0,"playing":false,"album":"Ja, Sára","artworkMimeType":"image\/jpeg","durationMicros":281346077,"artworkDataBase64":null}}
{"type":"data","diff":true,"payload":{"artworkDataBase64":"\/9j\/4AAQSkZJRgABAQAAS..."}}
{"type":"data","diff":true,"payload":{"timestampEpochMicros":1747260249656367,"elapsedTimeMicros":75372614}}
{"type":"data","diff":true,"payload":{"timestampEpochMicros":1747260311282554,"elapsedTimeMicros":0,"durationMicros":281000000}}
{"type":"data","diff":true,"payload":{"timestampEpochMicros":1747260312118660,"playing":true,"durationMicros":281346077}}
{"type":"data","diff":true,"payload":{"timestampEpochMicros":1747260324723482,"elapsedTimeMicros":12772000,"playing":false}}
```

The artwork data is shortened for brevity.

## Why this works

According to the findings by [@My-Iris](https://github.com/Mx-Iris) in
[this comment](https://github.com/aviwad/LyricFever/issues/94#issuecomment-2746155419)
processes with a bundle identifier starting with `com.apple.`
are granted permission to access the MediaRemote framework.
The Perl platform binary `/usr/bin/perl`
is reported as having the bundle identifier `com.apple.perl` (or a variation).

You can confirm this by streaming log messages using the Console.app
whilst running the script:

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

### TODO's

- Objective-C code to launch and manage execution of the adapter script
  and parse its output according to the rules described above
- Example project on how to use the adapter framework and script
  and instructions on how to bundle it with your app
- This library currently does not handle "peculiar media",
  which is reported media that is in a transition state
  from e.g. "song A by artist B" to "song C by artist D"
  having mixed metadata from both songs, e.g. "song C by artist B"
  (artist is updated too late)
- Solve FIXMEs and implement other TODOs that are located in source files

## Useful links

- Issues regarding MediaRemote breaking since macOS 15.4
  - https://github.com/vincentneo/LosslessSwitcher/issues/161
  - https://github.com/aviwad/LyricFever/issues/94
  - https://github.com/TheBoredTeam/boring.notch/issues/417
  - https://community.folivora.ai/t/now-playing-is-no-longer-working-on-macos-15-4/42802/11
  - https://github.com/ungive/discord-music-presence/issues/165
  - https://github.com/ungive/discord-music-presence/issues/245
  - https://github.com/kirtan-shah/nowplaying-cli/issues/28
  - https://github.com/FelixKratz/SketchyBar/issues/708
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

This project is licensed under the BSD 3-Clause License.
See [LICENSE](./LICENSE) for details.

Copyright (c) 2025 Jonas van den Berg
