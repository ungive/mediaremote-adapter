import Foundation

public class MediaController {

    private var perlScriptPath: String? {
        guard let path = Bundle.module.path(forResource: "run", ofType: "pl") else {
            assertionFailure("run.pl script not found in bundle resources.")
            return nil
        }
        return path
    }

    private var listeningProcess: Process?
    public var onTrackInfoReceived: ((Data) -> Void)?
    public var onListenerTerminated: (() -> Void)?

    public init() {}

    private var libraryPath: String? {
        let bundle = Bundle(for: MediaController.self)
        guard let path = bundle.executablePath else {
            assertionFailure("Could not locate the executable path for the MediaRemoteAdapter framework.")
            return nil
        }
        return path
    }

    @discardableResult
    private func runPerlCommand(arguments: [String]) -> (output: String?, error: String?, terminationStatus: Int32) {
        guard let scriptPath = perlScriptPath else {
            return (nil, "Perl script not found.", -1)
        }
        guard let libraryPath = libraryPath else {
            return (nil, "Dynamic library path not found.", -1)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptPath, libraryPath] + arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            return (output, errorOutput, process.terminationStatus)
        } catch {
            return (nil, error.localizedDescription, -1)
        }
    }

    public func startListening() {
        guard listeningProcess == nil else {
            print("Listener process is already running.")
            return
        }

        guard let scriptPath = perlScriptPath else {
            return
        }
        guard let libraryPath = libraryPath else {
            return
        }

        listeningProcess = Process()
        listeningProcess?.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        listeningProcess?.arguments = [scriptPath, libraryPath, "loop"]

        let outputPipe = Pipe()
        listeningProcess?.standardOutput = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty {
                outputPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                self?.onTrackInfoReceived?(data)
            }
        }

        listeningProcess?.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.listeningProcess = nil
                self?.onListenerTerminated?()
            }
        }

        do {
            try listeningProcess?.run()
        } catch {
            print("Failed to start listening process: \(error)")
            listeningProcess = nil
        }
    }

    public func stopListening() {
        listeningProcess?.terminate()
        listeningProcess = nil
    }

    public func play() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["play"])
        }
    }

    public func pause() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["pause"])
        }
    }

    public func togglePlayPause() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["toggle_play_pause"])
        }
    }

    public func nextTrack() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["next_track"])
        }
    }

    public func previousTrack() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["previous_track"])
        }
    }
    
    public func stop() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["stop"])
        }
    }

    public func setTime(seconds: Double) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["set_time", String(seconds)])
        }
    }
} 