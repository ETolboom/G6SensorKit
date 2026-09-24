// swift-tools-version: 5.9
//
//  Package.swift
//  G6SensorKit
//
//  Copyright © 2026 Nightscout Foundation. MIT License.
//  Portions adapted from CGMBLEKit, Copyright © 2015 Nathan Racklyeft (MIT).
//

import PackageDescription

let package = Package(
    name: "G6SensorCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "G6SensorCore", targets: ["G6SensorCore"]),
    ],
    targets: [
        .target(
            name: "G6SensorCore",
            path: "Sources/G6SensorCore"
        ),
        .testTarget(
            name: "G6SensorCoreTests",
            dependencies: ["G6SensorCore"],
            path: "Tests/G6SensorCoreTests"
        ),
    ]
)
