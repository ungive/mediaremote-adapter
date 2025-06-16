# MediaRemoteAdapter

A Swift package that allows macOS applications to control media playback and receive track information by bridging through the system's entitled Perl interpreter. It serves as a workaround for the `MediaRemote.framework` restrictions introduced in macOS 15.4.

## How It Works

This package is composed of two main targets:
1.  **`MediaRemoteAdapter` (Swift):** A public Swift module that provides a simple `MediaController` class. Your application interacts exclusively with this class.
2.  **`CIMediaRemote` (Objective-C):** An internal C-language module containing the Objective-C code that makes the actual calls to the private `MediaRemote.framework` APIs.

The `MediaController` does **not** call the Objective-C code directly. Instead, it executes a bundled Perl script (`run.pl`) which is signed by Apple and has the necessary entitlements to access the MediaRemote service. This script dynamically loads the compiled `CIMediaRemote` library (`.dylib`) and acts as a sandboxed bridge, passing commands in and streaming track data out.

This architecture provides the permissions of the original workaround with the safety and convenience of a modern, source-based Swift Package.

## Installation

You can add `MediaRemoteAdapter` to your project as a Swift Package dependency.

1.  In Xcode, open your project and navigate to **File > Add Packages...**
2.  Enter the repository URL: `https://github.com/ejbills/mediaremote-adapter.git`
3.  Choose the `MediaRemoteAdapter` product and add it to your application's target.

### Important: Embedding the Framework

After adding the package, you must ensure the framework is correctly embedded and signed in your application target.

1.  In the Project Navigator, select your project, then select your main application target.
2.  Go to the **General** tab.
3.  Find the **"Frameworks, Libraries, and Embedded Content"** section.
4.  The `MediaRemoteAdapter.framework` should be listed.
5.  Change its setting from "Do Not Embed" to **"Embed & Sign"**.

This step is crucial. It ensures the framework is copied into your app and signed with the same developer identity, which is required by macOS.

## Usage

Here is a basic example of how to use `MediaController`.

```swift
import MediaRemoteAdapter
import Foundation

class YourAppController {
    let mediaController = MediaController()

    init() {
        // Handle incoming track data
        mediaController.onTrackInfoReceived = { jsonData in
            // The data is raw JSON from the Perl script.
            // You'll need to decode it.
            print("Received track data: \(String(data: jsonData, encoding: .utf8) ?? "-")")

            // Example of decoding (you should define a proper Codable struct)
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                print("Payload: \(json["payload"] ?? [:])")
            }
        }

        // Handle listener termination
        mediaController.onListenerTerminated = {
            print("Listener process was terminated.")
        }
    }

    func setupAndStart() {
        // Start listening for media events in the background
        mediaController.startListening()
    }

    func playMusic() {
        mediaController.play()
    }

    func pauseMusic() {
        mediaController.pause()
    }

    func nextTrack() {
        mediaController.nextTrack()
    }

    func stopListening() {
        mediaController.stopListening()
    }
}
```

## API Overview

### `MediaController()`
Initializes a new controller.

### `var onTrackInfoReceived: ((Data) -> Void)?`
A closure that is called with raw JSON `Data` whenever new track information is available.

### `var onListenerTerminated: (() -> Void)?`
A closure that is called if the background listener process terminates unexpectedly.

### `startListening()`
Spawns the background Perl process to begin listening for media events.

### `stopListening()`
Terminates the background listener process.

### Playback Commands
These functions send a command to the background process and then exit. They are asynchronous and run on a global dispatch queue.
- `play()`
- `pause()`
- `togglePlayPause()`
- `nextTrack()`
- `previousTrack()`
- `stop()`
- `setTime(seconds: Double)`

## License

This project is licensed under the BSD 3-Clause License. See the [LICENSE](LICENSE) file for details.
