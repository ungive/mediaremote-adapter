// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "MediaRemoteAdapter",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "MediaRemoteAdapter",
            targets: ["MediaRemoteAdapter"]),
        .library(
            name: "CIMediaRemote",
            type: .dynamic,
            targets: ["CIMediaRemote"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MediaRemoteAdapter",
            dependencies: ["CIMediaRemote"],
            resources: [
                .copy("Resources/run.pl")
            ]
        ),
        .target(
            name: "CIMediaRemote",
            dependencies: [],
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-fno-objc-arc"])
            ],
            linkerSettings: [
                .unsafeFlags(["-framework", "Foundation"]),
                .unsafeFlags(["-framework", "AppKit"])
            ]
        )
    ]
) 