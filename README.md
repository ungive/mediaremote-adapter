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

## Integrating with a Swift Application

Here is a complete example of how you could integrate this into a Swift application.

**Important:** You must bundle the `MediaRemoteAdapter.framework` and the `run.pl` script with your application and ensure the paths are resolved correctly at runtime.

```swift
import Foundation

class MediaController {

    private var process: Process?
    private let frameworkPath: String
    private let scriptPath: String

    init?() {
        // Ensure the framework and script are bundled with your app.
        guard let frameworkPath = Bundle.main.path(forResource: "MediaRemoteAdapter", ofType: "framework"),
              let scriptPath = Bundle.main.path(forResource: "run", ofType: "pl") else {
            assertionFailure("MediaRemoteAdapter.framework or run.pl not found in app bundle.")
            return nil
        }
        self.frameworkPath = frameworkPath
        self.scriptPath = scriptPath
        
        startMonitoring()
    }

    func startMonitoring() {
        process = Process()
        process?.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process?.arguments = [scriptPath, frameworkPath, "loop"]

        let pipe = Pipe()
        process?.standardOutput = pipe
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8) {
                // Each JSON object is printed on a new line
                let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    self.parseMediaInfo(jsonString: line)
                }
            }
        }
        
        do {
            try process?.run()
        } catch {
            print("Failed to launch monitoring process: \(error.localizedDescription)")
        }
    }
    
    private func parseMediaInfo(jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else { return }
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                // Now you have a dictionary with media info.
                // You can update your UI from here.
                DispatchQueue.main.async {
                    print("Received Media Info: \(json)")
                    // e.g., if let payload = json["payload"] as? [String: Any],
                    // let title = payload["title"] as? String { ... }
                }
            }
        } catch {
            print("Failed to parse JSON: \(error.localizedDescription)")
        }
    }

    func sendCommand(_ command: String, args: [String] = []) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [scriptPath, frameworkPath, command] + args
        
        do {
            try task.run()
            task.waitUntilExit()
            // You could check task.terminationStatus if needed.
        } catch {
            print("Failed to send command '\(command)': \(error.localizedDescription)")
        }
    }

    // MARK: - Public Controls

    func play() { sendCommand("play") }
    func pause() { sendCommand("pause") }
    func togglePlayPause() { sendCommand("toggle") }
    func nextTrack() { sendCommand("next") }
    func previousTrack() { sendCommand("prev") }
    func stop() { sendCommand("stop") }
    func seek(to seconds: Double) { sendCommand("set_time", args: [String(seconds)]) }
}
```

## License

This project is licensed under the **BSD 3-Clause License**. See the `LICENSE` file for details.

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
