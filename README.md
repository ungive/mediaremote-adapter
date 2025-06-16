# MediaRemote Adapter: Access "Now Playing" Info on macOS Sonoma 15.4+

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

## The Problem

Since **macOS Sonoma 15.4**, Apple has restricted access to the private `MediaRemote.framework`. Previously, applications could use functions like `MRMediaRemoteGetNowPlayingInfo()` to get metadata about the currently playing song, track, or video.

Now, calling these functions from a standard application simply returns no data or fails silently. This is because access now requires a special entitlement that is only granted to Apple's own processes. This change broke numerous applications that relied on this functionality for features like Discord Rich Presence, menu bar widgets, and more.

## The Solution

This project provides a workaround by leveraging a loophole in the new restrictions: processes with a bundle identifier starting with `com.apple.` are still granted the necessary entitlement.

This repository contains two key components:
1.  **A pre-compiled Objective-C framework** (`MediaRemoteAdapter.framework`) that does the work of calling the `MediaRemote` APIs.
2.  **A Perl script** (`scripts/run.pl`) that acts as a trusted host process. Because the system's Perl interpreter has the bundle ID `com.apple.perl`, it is granted the entitlement. The script dynamically loads our framework into its own memory space, allowing the framework's code to run with the necessary permissions.

Your application launches this Perl script as a background helper tool and reads the JSON data it prints to standard output.

## Features

- **Bypass macOS 15.4+ Restrictions:** The primary purpose of this library.
- **Simple Data Flow:** Receive real-time media updates as a stream of JSON strings.
- **Full Metadata:** Get title, artist, album, duration, elapsed time, artwork, and more.
- **Easy to Build:** A simple shell script compiles the framework.
- **Easy to Integrate:** A Swift wrapper class is provided below to make integration trivial.

## Build Instructions

A helper script is provided to automate the build process.

```bash
# Build the framework
./build.sh
```

The compiled `MediaRemoteAdapter.framework` will be located in the `build/` directory.

## Xcode Integration Guide

You cannot link this framework directly. You must bundle it with your app and launch it via the provided Perl script. Here is a complete guide to do this using Swift.

### Step 1: Add Files to Your Xcode Project

1.  **Embed the Framework:** Run `./build.sh` to create the framework. Drag `MediaRemoteAdapter.framework` from the `build/` directory in Finder into your project's **"Frameworks, Libraries, and Embedded Content"** section. Set it to **"Embed & Sign"**.
2.  **Copy the Scripts Folder:** Drag the `scripts` directory from this repository into your Xcode project navigator. Choose **"Create folder references"** when prompted. Ensure the folder is added to your app target's **"Copy Bundle Resources"** build phase.

### Step 2: Create a Swift Wrapper

Add the following `MediaManager` class to your project. It handles launching the helper tool and listening for data.

```swift
// MediaManager.swift

import Foundation

class MediaManager {
    
    // A callback to pass the raw JSON string back to the app
    var onDataReceived: ((String) -> Void)?
    
    private var helperProcess: Process?
    private let pipe = Pipe()

    func start() {
        // 1. Ensure the helper isn't already running
        guard helperProcess == nil else {
            print("Helper process is already running.")
            return
        }
        
        // 2. Locate the bundled framework and script
        guard let frameworkPath = Bundle.main.path(forResource: "MediaRemoteAdapter", ofType: "framework"),
              let scriptPath = Bundle.main.path(forResource: "run", ofType: "pl", inDirectory: "scripts") else {
            print("Error: Could not find bundled framework or script.")
            return
        }

        // 3. Configure the process to run the Perl script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptPath, frameworkPath]
        process.standardOutput = pipe
        
        // 4. Set up an asynchronous reader on the pipe's output
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty {
                // EOF
                print("Helper process pipe closed.")
                self?.pipe.fileHandleForReading.readabilityHandler = nil
            } else if let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                // We received data, pass it to the callback on the main thread
                DispatchQueue.main.async {
                    self?.onDataReceived?(line)
                }
            }
        }
        
        // 5. Launch the process
        do {
            try process.run()
            self.helperProcess = process
            print("Started helper process.")
        } catch {
            print("Failed to start helper process: \(error)")
        }
    }

    func stop() {
        guard let helperProcess = helperProcess else { return }
        
        print("Stopping helper process.")
        pipe.fileHandleForReading.readabilityHandler = nil
        helperProcess.terminate() // Sends SIGTERM
        self.helperProcess = nil
    }
    
    // Make sure to stop the process when the manager is deallocated
    deinit {
        stop()
    }
}
```

### Step 3: Use the Manager in Your App (SwiftUI Example)

```swift
// ContentView.swift

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    var body: some View {
        VStack(spacing: 20) {
            Text("MediaRemote Workaround")
                .font(.largeTitle)
            
            Text(viewModel.mediaInfo)
                .padding()
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(8)
            
            Button("Start Monitoring", action: viewModel.start)
            Button("Stop Monitoring", action: viewModel.stop)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

// ViewModel to manage the state and interaction
@MainActor
class ContentViewModel: ObservableObject {
    @Published var mediaInfo: String = "Press 'Start' to monitor media..."
    private let mediaManager = MediaManager()

    init() {
        // Set the callback
        mediaManager.onDataReceived = { [weak self] jsonString in
            // For now, just display the raw JSON.
            // In a real app, you would decode this with JSONDecoder.
            self?.mediaInfo = jsonString
        }
    }
    
    func start() {
        mediaManager.start()
    }
    
    func stop() {
        mediaManager.stop()
        mediaInfo = "Monitoring stopped."
    }
}
```

## Command Control

Beyond listening for updates, you can now send playback commands. The script takes an optional command argument after the framework path.

**Base command structure:**
```bash
/usr/bin/perl ./scripts/run.pl /path/to/framework.framework [command]
```

### Supported Commands

| Command    | Description                               | Example                                                                          |
| :--------- | :---------------------------------------- | :------------------------------------------------------------------------------- |
| `loop`     | (Default) Listens for media changes and prints JSON updates indefinitely. | `.../run.pl .../framework`                                                       |
| `play`     | Sends the play command.                   | `.../run.pl .../framework play`                                                  |
| `pause`    | Sends the pause command.                  | `.../run.pl .../framework pause`                                                 |
| `toggle`   | Toggles between play and pause.           | `.../run.pl .../framework toggle`                                                |
| `next`     | Skips to the next track.                  | `.../run.pl .../framework next`                                                  |
| `prev`     | Goes to the previous track.               | `.../run.pl .../framework prev`                                                  |
| `stop`     | Stops playback.                           | `.../run.pl .../framework stop`                                                  |
| `set_time` | Seeks to a specific time in the track.    | `.../run.pl .../framework set_time 60` (jumps to 60 seconds) |

## Projects that use this library

- [Music Presence](https://musicpresence.app) is a cross-platform desktop application
  for showing what you are listening to in your Discord status.
  It uses this library since version [2.3.1](https://github.com/ungive/discord-music-presence/releases/tag/v2.3.1)
  to detect media from all media players again.

## Contributing

This project aims to be a universal drop-in replacement
for directly using the MediaRemote framework on Mac.

If you have the time to contribute, you are more than welcome to do so,
any help to improve this project is greatly appreciated!

## Useful links

- Issues regarding MediaRemote breaking since macOS 15.4
  - https://github.com/vincentneo/LosslessSwitcher/issues/161
  - https://github.com/aviwad/LyricFever/issues/94
  - https://github.com/TheBoredTeam/boring.notch/issues/417
  - https://community.folivora.ai/t/now-playing-is-no-longer-working-on-macos-15-4/42802/11
  - https://github.com/ungive/discord-music-presence/issues/165
  - https://github.com/ungive/discord-music-presence/issues/245
  - https://github.com/kirtan-shah/nowplaying-cli/issues/28

## Acknowledgements

Thank you [@My-Iris](https://github.com/Mx-Iris)
for providing insight into the changes made since macOS 15.4:
[aviwad/LyricFever#94](https://github.com/aviwad/LyricFever/issues/94#issuecomment-2746155419)

## License

This file is licensed under the BSD 3-Clause License.
See [LICENSE](./LICENSE) for details.

Copyright (c) 2025 Jonas van den Berg
