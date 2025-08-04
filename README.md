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
![](https://img.shields.io/static/v1?label=macOS&message=macOS%2026.0%20%2825A5316i%29&labelColor=444&color=blue)
![](https://img.shields.io/static/v1?label=last%20tested&message=Thu%20Jul%2024%2002%3A24%3A11%20CEST%202025&labelColor=444&color)
<!-- BADGES END -->

# MediaRemote Adapter

Get now playing information using the MediaRemote framework
on all macOS versions, including 15.4 and above.

This works by using a system binary &ndash; `/usr/bin/perl` in this case &ndash;
which is entitled to use the MediaRemote framework
and by dynamically loading a custom helper framework
that prints real-time updates to stdout.

## Example

Install the [media-control](https://github.com/ungive/media-control)
CLI tool to see this project in action. Works on all macOS versions:

```
$ brew tap ungive/media-control
$ brew install media-control
$ media-control stream
```

## Usage

This project provides a Perl script
with a well-defined CLI interface that you can invoke from your app
in order to read now playing information and control media players.
The [mediaremote-adapter.pl](./bin/mediaremote-adapter.pl) script
needs to be bundled with your app,
alongside the `MediaRemoteAdapter.framework`
which is exposed as a CMake target in [CMakeLists.txt](./CMakeLists.txt).
You can find instructions to build the framework in the next section.

The script must then be invoked like this:

```
/usr/bin/perl /path/to/mediaremote-adapter.pl /path/to/MediaRemoteAdapter.framework COMMAND
```

For the `test` command, an additional helper path is required:

```
/usr/bin/perl /path/to/mediaremote-adapter.pl /path/to/MediaRemoteAdapter.framework /path/to/NowPlayingTestClient test
```

Where `COMMAND` is one of the commands listed below.

> [!NOTE]
> A Swift package and an Objective-C library
> that you can directly include in your project is underway.

> [!WARNING]
> This project is still in development
> and the API may experience breaking changes across minor revisions.

## Build from source

```
$ git clone https://github.com/ungive/mediaremote-adapter.git
$ cd mediaremote-adapter
$ mkdir build && cd build
$ cmake ..
$ cmake --build .
$ cd ..
$ FRAMEWORK_PATH=$(realpath ./build/MediaRemoteAdapter.framework)
$ /usr/bin/perl ./bin/mediaremote-adapter.pl "$FRAMEWORK_PATH" stream
```

This creates the `MediaRemoteAdapter.framework` in the build directory,
which must be *bundled* with your app, but *not linked against*.
The framework is only used by the script
and must merely be passed as a script argument.

The framework is built for all of the following architectures:
`x86_64` `arm64` `arm64e`

The build process also creates the `NowPlayingTestClient` executable
in the build directory, which is required for the `test` command:

```
$ HELPER_PATH=$(realpath ./build/NowPlayingTestClient)
$ /usr/bin/perl ./bin/mediaremote-adapter.pl "$FRAMEWORK_PATH" "$HELPER_PATH" test
```


## Commands

- [get](#get)
- [stream](#stream)
- [send COMMAND](#send-command)
- [seek POSITION](#seek-position)
- [shuffle MODE](#shuffle-mode)
- [repeat MODE](#repeat-mode)
- [speed SPEED](#speed-speed)
- [test](#test)

### get

Prints now playing information once with all available metadata.

Output is encoded as JSON and characterized by either `null`
or a dictionary with any of the following keys:

> `bundleIdentifier`
`parentApplicationBundleIdentifier`
`playing`
`title`
`artist`
`album`
`duration`
`elapsedTime`
`timestamp`
`artworkMimeType`
`artworkData`
`chapterNumber`
`composer`
`genre`
`isAdvertisement`
`isBanned`
`isInWishList`
`isLiked`
`isMusicApp`
`playbackRate`
`prohibitsSkip`
`queueIndex`
`radioStationIdentifier`
`repeatMode`
`shuffleMode`
`startTime`
`supportsFastForward15Seconds`
`supportsIsBanned`
`supportsIsLiked`
`supportsRewind15Seconds`
`totalChapterCount`
`totalDiscCount`
`totalQueueCount`
`totalTrackCount`
`trackNumber`
`uniqueIdentifier`
`contentItemIdentifier`
`radioStationHash`
`mediaType`

The following mandatory keys never have a null value:
`bundleIdentifier`
`playing`
`title`.
If any of the mandatory keys cannot be determined,
the command prints `null`.
Media without a title is considered invalid.

The `mediaType` may contain one of the following values:
- `MRMediaRemoteMediaTypeMusic`
- `kMRMediaRemoteNowPlayingInfoTypeAudio`
- Possibly others, this key is not very well documented

**Caveats**

Metadata such as `artworkData` and `artworkMimeType`
often takes a bit of time to load
and may not appear in the output in all cases.
Do not rely on this key to be present reliably.
Either use the `stream` command or poll `get` regularly,
to ensure you get the artwork data *eventually*.

**Options**

`--micros`&ensp;Replaces the following keys with microsecond equivalents:

| Original key  | Converted key name     | Comment                 |
| ------------- | ---------------------- | ----------------------- |
| `duration`    | `durationMicros`       | -                       |
| `elapsedTime` | `elapsedTimeMicros`    | -                       |
| `timestamp`   | `timestampEpochMicros` | Converted to epoch time |

---

### stream

Streams now playing information updates in real-time
until the script receives a SIGTERM signal.

Output is encoded as JSON and characterized by
a dictionary with the following keys:

> `type`
`diff`
`payload`

The value of `type` is always set to `"data"`.

`diff` is a boolean that indicates whether the `payload`
contains only fields whose values have been updated.
If set to `false`,
the payload is to be considered the current now playing state,
regardless of any payloads that were sent in the past.
If set to `true` on the other hand,
the last sent non-diff payload must be updated with these new values,
in order to have a representation of the the current now playing state.
**Diffing is enabled by default, but can be disabled with a command line flag.**

`payload` contains the now playing information and is a dictionary
that is structurally identical to the output of the `get` command,
with the same keys. It is never `null` though.
No keys are set at all,
when no media player is reporting now playing information.

**Options**

`--no-diff`&ensp;Disables diffing. `diff` is always `false`
and `payload` always contains all current information.

`--debounce=N`&ensp;Adds a debounce delay in milliseconds
between the point where changes are detected
and when they are printed.
If a new update comes in during delaying,
the delay is restarted and all updates are merged.
This is useful to prevent bursts of smaller updates.
The default is 0.

`--micros`&ensp;Identical to the `--micros` option of the `get` command.

---

### send COMMAND

Sends a MediaRemote command to the now playing application.

The value for `COMMAND` must be a valid ID from the table below.

|  ID   | MediaRemote key         | Description                   |
| :---: | ----------------------- | ----------------------------- |
|   0   | kMRPlay                 | Start playback                |
|   1   | kMRPause                | Pause playback                |
|   2   | kMRTogglePlayPause      | Toggle between play and pause |
|   3   | kMRStop                 | Stop playback                 |
|   4   | kMRNextTrack            | Skip to the next track        |
|   5   | kMRPreviousTrack        | Return to the previous track  |
|   6   | kMRToggleShuffle        | Toggle shuffle mode           |
|   7   | kMRToggleRepeat         | Toggle repeat mode            |
|   8   | kMRStartForwardSeek     | Start seeking forward         |
|   9   | kMREndForwardSeek       | Stop seeking forward          |
|  10   | kMRStartBackwardSeek    | Start seeking backward        |
|  11   | kMREndBackwardSeek      | Stop seeking backward         |
|  12   | kMRGoBackFifteenSeconds | Go back 15 seconds            |
|  13   | kMRSkipFifteenSeconds   | Skip ahead 15 seconds         |

---

### seek POSITION

Seeks to a specific timeline position with the now playing application.

The value for `POSITION` must a valid positive integer.
The unit is microseconds.

---

### shuffle MODE

Sets the shuffle mode.

The value for `MODE` must be a valid ID from the table below.

|  ID   | Description    |
| :---: | -------------- |
|   1   | Disable        |
|   2   | Shuffle albums |
|   3   | Shuffle tracks |

---

### repeat MODE

Sets the repeat mode.

The value for `MODE` must be a valid ID from the table below.

|  ID   | Description     |
| :---: | --------------- |
|   1   | Disable         |
|   2   | Repeat track    |
|   3   | Repeat playlist |

---

### speed SPEED

Sets the playback speed.

The value for `SPEED` must be a valid positive integer.

---

### test

Verifies if the MediaRemote Adapter is functioning correctly.

This can be integrated into your app to help confirm that our adapter is still effective and select fallback options if necessary since future macOS updates may break it again.

**Usage**

```
/usr/bin/perl /path/to/mediaremote-adapter.pl /path/to/MediaRemoteAdapter.framework /path/to/NowPlayingTestClient test
```

Note that the `test` command requires the absolute path to the `NowPlayingTestClient` helper executable as the second argument (before the command name).

**Output**

The command returns with an exit code of `0` if the adapter is functioning correctly, or `1` if it is not.

**How it works**

1. First, it attempts to get now playing information normally
2. If no media is detected, launches a helper process (`NowPlayingTestClient`) that simulates media playback
3. Attempts to retrieve now playing information again
4. Terminates the helper process
5. Reports whether the adapter can successfully detect the simulated media

**IMPORTANT: May interfere with other apps using MediaRemote**: The test can create a fake media entry that will briefly appear as the now playing app. This only happens when no other media is playing. Since the helper process has no bundle identifier, it is mostly ignored by the `stream` and `get` commands — `stream` won't update, and `get` will print `null`. However, both commands will also print error messages to stderr about the missing bundle identifier.

---

## Built-in fixes

This library has some fixes built-in
to accomodate for inconsistencies within the MediaRemote framework:

- Artwork data sometimes unloads for a brief moment,
  e.g. when changing the current timeline position of a track.
  To combat this, artwork data is reused when the track has not changed,
  the track had artwork data before and the artwork data has disappeared.
  This fix is applied when using the `stream` command

If you need a way to disable any or all of these fixes,
please open an issue or create a pull request.

---

## Implementation notes

- Consider `NSJSONSerialization` for JSON deserialization.
  This is what is used for encoding
- You can use `NSData`'s `initWithBase64EncodedString`
  for decoding of base64 data
- Every line printed to stderr is an error message.
  If the script did not exit with a non-zero exit code,
  then any of these errors are non-fatal and can be safely ignored
- Other apps using MediaRemote Adapter may run `test` which should not interfere with the `stream` and `get` commands, but will generate a missing bundle identifier error message, which can be ignored. See the `test` command section for more information.
- You should not reinvoke the script when a fatal error occurs
  (non-zero exit code)
- Make sure to pass the absolute path of the bundled framework and helper executable
  as arguments and not a relative path

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

## Motivation

This project was created due to the MediaRemote framework
being completely non-functional when being loaded directly from within an app,
starting with macOS 15.4 (see the numerous issues linked below).

The aim of this project is to provide a tool (and perhaps soon a full library)
that serves as a fully functional alternative to using MediaRemote directly
and perhaps to inspire Apple to give us a public API
to read now playing information and control media playback on the device
(see the note at the top of this file).

## Projects that use this library

- [Music Presence](https://musicpresence.app) is a cross-platform desktop application
  for showing what you are listening to in your Discord status.
  It uses this library since version [2.3.1](https://github.com/ungive/discord-music-presence/releases/tag/v2.3.1)
  to detect media from all media players again.
- [media-control](https://github.com/ungive/media-control)
  is a CLI tool to control and observe media playback on any macOS version.
  You can install it directly via brew: `$ brew tap ungive/media-control && brew install media-control`

*If you use this library in your project, please
[let me know](https://github.com/ungive/mediaremote-adapter/issues)!*

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
