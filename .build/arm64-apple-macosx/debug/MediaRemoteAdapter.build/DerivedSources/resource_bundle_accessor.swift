import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("MediaRemoteAdapter_MediaRemoteAdapter.bundle").path
        let buildPath = "/Users/ethanbills/Documents/Github/mediaremote-adapter/.build/arm64-apple-macosx/debug/MediaRemoteAdapter_MediaRemoteAdapter.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}