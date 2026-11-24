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
        .library(name: "PVRemoteLibrary", targets: ["PVRemoteLibrary"]),
        .library(name: "PVRemoteLibraryRomM", targets: ["PVRemoteLibraryRomM"])
    ],
    dependencies: [
        .package(url: "https://github.com/Provenance-Emu/PVSystems.git", from: "1.0.0"),
        .package(url: "https://github.com/Provenance-Emu/emulator-content-server.git", revision: "7b30839778e502573ee0cfb91c4bf94a1de51fa8")
    ],
    targets: [
        .target(
            name: "PVRemoteLibrary",
            dependencies: [.product(name: "PVSystems", package: "PVSystems")]
        ),
        .target(
            name: "PVRemoteLibraryRomM",
            dependencies: [
                "PVRemoteLibrary",
                .product(name: "PVSystems", package: "PVSystems"),
                .product(name: "RomMClient", package: "emulator-content-server")
            ]
        ),
        .testTarget(
            name: "PVRemoteLibraryTests",
            dependencies: ["PVRemoteLibrary", .product(name: "PVSystems", package: "PVSystems")]
        )
    ]
)
