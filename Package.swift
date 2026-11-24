// swift-tools-version:6.0
import PackageDescription

// One model of "a game somewhere": local, on an emulator content server, on a
// RomM share or on a nearby peer. Shared by Provenance, iFly and iCube.
// No UIKit, SwiftUI, Realm or SwiftData: `swift test` runs on the Mac.
// Design: Provenance docs/superpowers/specs/2026-11-23-shared-remote-library-browser-design.md
let package = Package(
    name: "PVRemoteLibrary",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "PVRemoteLibrary", targets: ["PVRemoteLibrary"])
    ],
    dependencies: [
        // Versioned dependencies only: a package pinned to a revision cannot be used
        // from a package that apps depend on by version. That is why the content
        // server and RomM sources live in the apps until that client has stable tags.
        .package(url: "https://github.com/Provenance-Emu/PVSystems.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "PVRemoteLibrary",
            dependencies: [.product(name: "PVSystems", package: "PVSystems")]
        ),
        .testTarget(
            name: "PVRemoteLibraryTests",
            dependencies: ["PVRemoteLibrary", .product(name: "PVSystems", package: "PVSystems")]
        )
    ]
)
