// swift-tools-version:5.9
//  Look4Sat iOS port — Swift package manifest
//  License: GPL-3.0
//
//  This package builds the pure-algorithm layer (SGP4/SDP4 propagation,
//  celestial math, TLE parsing, pass prediction) as a cross-platform target.
//  The iOS UI layer (SwiftUI app shell) lives in app/Look4SatApp.swift and
//  is built by the Xcode project that wraps this package; it is intentionally
//  NOT part of this package so the algorithm library stays dependency-free.
import PackageDescription

let package = Package(
    name: "Look4Sat",
    platforms: [
        .iOS(.v16),
        .macOS(.v12)
    ],
    products: [
        .library(name: "Look4SatCore", targets: ["Look4SatCore"]),
        .executable(name: "look4sat-cli", targets: ["look4sat-cli"])
    ],
    targets: [
        .target(
            name: "Look4SatCore",
            path: "Look4Sat/Look4Sat"
        ),
        .executableTarget(
            name: "look4sat-cli",
            dependencies: ["Look4SatCore"],
            path: "look4sat-cli"
        ),
        .testTarget(
            name: "Look4SatTests",
            dependencies: ["Look4SatCore"],
            path: "Look4SatTests"
        )
    ]
)
