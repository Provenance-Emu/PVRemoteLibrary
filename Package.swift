// swift-tools-version:6.0
import Foundation
import PackageDescription

// One model of "a game somewhere": local, on an emulator content server, on a
// RomM share or on a nearby peer. Shared by Provenance, iFly and iCube.
// No UIKit, SwiftUI, Realm or SwiftData: `swift test` runs on the Mac.
// Design: Provenance docs/superpowers/specs/2026-11-23-shared-remote-library-browser-design.md

// A version tag resolves to the prebuilt XCFrameworks from that tag's GitHub release;
// `main` always builds from source. The release workflow fills this in on the tagged
// commit only, so it stays `nil` on every branch.
// Set PV_BUILD_FROM_SOURCE=1 to build a tagged version from source instead.
let binaryRelease: (version: String, checksums: [String: String])? = nil

let environment = ProcessInfo.processInfo.environment
let buildFromSource = binaryRelease == nil || environment["PV_BUILD_FROM_SOURCE"] != nil
// The release workflow builds the frameworks it publishes from dynamic products, one
// module at a time, and names the ones already built so later modules link them
// instead of compiling them in again.
let buildingRelease = environment["PV_XCFRAMEWORK_BUILD"] != nil
let libraryType: Product.Library.LibraryType? = buildingRelease ? .dynamic : nil
let prebuilt = Set((environment["PV_XCFRAMEWORK_PREBUILT"] ?? "").split(separator: " ").map(String.init))

func module(_ source: Target) -> Target {
    prebuilt.contains(source.name)
        ? .binaryTarget(name: source.name, path: ".xcframework-build/\(source.name).xcframework")
        : source
}

// A product made only of a prebuilt framework cannot ask for a linkage type.
let libraryTypeFor: (String) -> Product.Library.LibraryType? = { module in
    prebuilt.contains(module) ? nil : libraryType
}

let systems: Target.Dependency = .product(name: "PVSystems", package: "PVSystems")

let sourceTargets: [Target] = [
    module(.target(name: "PVRemoteLibrary", dependencies: [systems])),
    // PVSystems is named here too: PVRemoteLibrary's interface imports it, and a prebuilt
    // framework does not pass its own dependencies on.
    module(.target(name: "PVRemoteLibraryUI", dependencies: ["PVRemoteLibrary", systems]))
] + (buildingRelease ? [] : [
    .testTarget(
        name: "PVRemoteLibraryTests",
        dependencies: ["PVRemoteLibrary", "PVRemoteLibraryUI", systems]
    )
])

let binaryTargets: [Target] = binaryRelease.map { release in
    release.checksums.sorted { $0.key < $1.key }.map { module, checksum in
        .binaryTarget(
            name: module,
            url: "https://github.com/Provenance-Emu/PVRemoteLibrary/releases/download/\(release.version)/\(module).xcframework.zip",
            checksum: checksum
        )
    } + [
        // What the prebuilt frameworks link against.
        .target(name: "PVRemoteLibraryDependencies", dependencies: [systems], path: "Sources/BinaryDependencies")
    ]
} ?? []

let package = Package(
    name: "PVRemoteLibrary",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    // Product names are the same in both modes, so consumers never change.
    products: buildFromSource ? [
        .library(name: "PVRemoteLibrary", type: libraryTypeFor("PVRemoteLibrary"), targets: ["PVRemoteLibrary"]),
        // Optional SwiftUI pieces every app draws the same way: transfer progress, source pill.
        .library(name: "PVRemoteLibraryUI", type: libraryTypeFor("PVRemoteLibraryUI"), targets: ["PVRemoteLibraryUI"])
    ] : [
        .library(name: "PVRemoteLibrary", targets: ["PVRemoteLibrary", "PVRemoteLibraryDependencies"]),
        .library(name: "PVRemoteLibraryUI", targets: ["PVRemoteLibraryUI", "PVRemoteLibrary", "PVRemoteLibraryDependencies"])
    ],
    dependencies: [
        // Versioned dependencies only: a package pinned to a revision cannot be used
        // from a package that apps depend on by version. That is why the content
        // server and RomM sources live in the apps until that client has stable tags.
        // 1.0.2 is the first PVSystems release with a prebuilt framework. An older one
        // would be compiled into PVRemoteLibrary's own framework.
        .package(url: "https://github.com/Provenance-Emu/PVSystems.git", from: "1.0.2")
    ],
    targets: buildFromSource ? sourceTargets : binaryTargets
)
