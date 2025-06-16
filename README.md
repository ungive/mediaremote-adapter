# MediaRemoteAdapter

A Swift package for macOS that provides a robust, modern interface for controlling media playback and receiving track information, designed to work around the sandboxing and entitlement restrictions of the private `MediaRemote.framework`.

## How It Works

This package uses a unique architecture to gain the necessary permissions for media control:

1.  **Swift `MediaController`:** The public API you interact with in your app. It's a simple, modern Swift class.
2.  **Objective-C Bridge:** An internal library containing the code that calls the private `MediaRemote.framework` functions.
3.  **Perl Interpreter:** The `MediaController` does not call the Objective-C code directly. Instead, it executes a bundled Perl script using the system's `/usr/bin/perl`, which has the necessary entitlements to access the media service.
4.  **Dynamic Loading:** At runtime, the Perl script dynamically loads the compiled Objective-C library, acting as a sandboxed bridge. It passes commands in from your app and streams track data back out over a pipe.

This approach provides the power of the private framework with the safety and convenience of a modern Swift Package.

## Installation

You can add `MediaRemoteAdapter` to your project using the Swift Package Manager.

1.  In Xcode, open your project and navigate to **File > Add Packages...**
2.  Enter the repository URL: `https://github.com/ejbills/mediaremote-adapter.git`
3.  Choose the `MediaRemoteAdapter` product and add it to your application's target.

### Important: Embedding the Framework

After adding the package, you must ensure the framework is correctly embedded and signed.

1.  In the Project Navigator, select your project, then select your main application target.
2.  Go to the **General** tab.
3.  Find the **"Frameworks, Libraries, and Embedded Content"** section.
4.  `MediaRemoteAdapter.framework` should be listed. Change its setting from "Do Not Embed" to **"Embed & Sign"**.

This crucial step copies the framework into your app and signs it with your developer identity, as required by macOS.

## Usage

Here is a basic example of how to use `MediaController`. For a complete, working example, see the `DockDoor` project.

```swift
import MediaRemoteAdapter
import Foundation

// It's recommended to create a Codable struct to represent the track data.
struct TrackInfo: Codable {
    let payload: Payload
    
    struct Payload: Codable {
        let title: String?
        let artist: String?
        let album: String?
        let isPlaying: Bool?
        let durationMicros: Double?
        let elapsedTimeMicros: Double?
        let applicationName: String?
    }
}


class YourAppController {
    let mediaController = MediaController()

    init() {
        // Handle incoming track data
        mediaController.onTrackInfoReceived = { jsonData in
            do {
                let trackInfo = try JSONDecoder().decode(TrackInfo.self, from: jsonData)
                print("Now Playing: \(trackInfo.payload.title ?? "N/A") - Playing: \(trackInfo.payload.isPlaying ?? false)")
            } catch {
                print("Failed to decode track info: \(error)")
            }
        }

        // Handle listener termination
        mediaController.onListenerTerminated = {
            print("MediaRemoteAdapter listener process was terminated.")
        }
    }

    func setupAndStart() {
        // Start listening for media events in the background.
        mediaController.startListening()
    }

    // All playback commands are asynchronous.
    func play() { mediaController.play() }
    func pause() { mediaController.pause() }
    func togglePlayPause() { mediaController.togglePlayPause() }
    func nextTrack() { mediaController.nextTrack() }
    func previousTrack() { mediaController.previousTrack() }
    func stop() { mediaController.stop() }
    
    func seek(to seconds: Double) {
        mediaController.setTime(seconds: seconds)
    }
}
```

## API Overview

### `MediaController()`
Initializes a new controller.

### `var onTrackInfoReceived: ((Data) -> Void)?`
A closure that is called with a raw JSON `Data` object whenever new track information is available. The data is a complete snapshot of the current state.

### `var onListenerTerminated: (() -> Void)?`
A closure that is called if the background listener process terminates unexpectedly. You may want to restart it here.

### `startListening()`
Spawns the background Perl process to begin listening for media events.

### `stopListening()`
Terminates the background listener process.

### Playback Commands
These functions send an asynchronous command to the background process.
- `play()`
- `pause()`
- `togglePlayPause()`
- `nextTrack()`
- `previousTrack()`
- `stop()`
- `setTime(seconds: Double)`

## License

This project is licensed under the BSD 3-Clause License. See the [LICENSE](LICENSE) file for details.
