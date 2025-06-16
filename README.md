# MediaRemote Adapter

A workaround for applications that use the private `MediaRemote.framework` on macOS and are affected by the permission changes introduced in macOS 15.4 (Sonoma). This project provides a helper framework and an entitled Perl script to regain control over media playback.

## The Problem

As of macOS 15.4, applications without a specific entitlement (`com.apple.private.mediaremote.send-commands` or `com.apple.private.mediaremote.receive-reminders`) can no longer send playback commands or receive media metadata. This breaks many third-party applications that provide custom media controls or display track information.

This project offers a solution by leveraging a pre-entitled host process: the system's own Perl interpreter, which possesses the necessary entitlements because it is signed by Apple.

## How It Works

The core of this workaround is a Perl script (`scripts/run.pl`) that dynamically loads our custom-built `MediaRemoteAdapter.framework`. The framework acts as a bridge, exposing two main functionalities managed through the entitled Perl process:

1.  **Listening for Media Info:** When run in `loop` mode, it registers for notifications from the MediaRemote service and streams any changes (track, artist, playback state, etc.) as JSON objects to `stdout`.
2.  **Sending Playback Commands:** The script can be called with commands like `play`, `pause`, or `next`. It loads the framework, sends the single command, and then exits.

This creates a simple, effective, and bidirectional communication channel between your application and the private MediaRemote framework.

## How to Build

A convenience script is provided. From the root of the project, simply run:

```bash
./build.sh
```

This will produce the `MediaRemoteAdapter.framework` inside the `build/` directory.

## How to Use

The framework is controlled via the `scripts/run.pl` Perl script. You must always provide the path to the built framework as the first argument.

### Listening for Media Information

To start listening for media changes, run the script with the `loop` command. It will run indefinitely, printing JSON objects to `stdout` whenever media information changes.

```bash
/usr/bin/perl ./scripts/run.pl ./build/MediaRemoteAdapter.framework loop
```

### Sending Playback Commands

To send a command, simply provide the command name as the second argument. 

| Command              | Description                               |
| -------------------- | ----------------------------------------- |
| `play`               | Starts playback.                          |
| `pause`              | Pauses playback.                          |
| `toggle`             | Toggles between play and pause.           |
| `next`               | Skips to the next track.                  |
| `prev`               | Skips to the previous track.              |
| `stop`               | Stops playback.                           |
| `set_time <seconds>` | Seeks to a specific time in the track.    |

**Examples:**

```bash
# Pause the music
/usr/bin/perl ./scripts/run.pl ./build/MediaRemoteAdapter.framework pause

# Skip to the next track
/usr/bin/perl ./scripts/run.pl ./build/MediaRemoteAdapter.framework next

# Seek to the 60-second mark of the current track
/usr/bin/perl ./scripts/run.pl ./build/MediaRemoteAdapter.framework set_time 60
```
