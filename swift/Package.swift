// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EdgeVeda",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "EdgeVeda",
            targets: ["EdgeVeda"]
        )
    ],
    dependencies: [],
    targets: [
        // C library target for FFI
        .target(
            name: "CEdgeVeda",
            dependencies: [],
            path: "Sources/CEdgeVeda",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("../../core/include")
            ],
            linkerSettings: [
                // Link against the edge_veda core library
                .linkedLibrary("edge_veda"),
                .linkedLibrary("c++"),
                // Add library search path for the compiled core library
                .unsafeFlags(["-L../../core/build"], .when(configuration: .debug)),
                .unsafeFlags(["-L../../core/build"], .when(configuration: .release))
            ]
        ),

        // Main Swift library
        .target(
            name: "EdgeVeda",
            dependencies: ["CEdgeVeda"],
            path: "Sources/EdgeVeda",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // Test target
        .testTarget(
            name: "EdgeVedaTests",
            dependencies: ["EdgeVeda"],
            path: "Tests/EdgeVedaTests"
        )
    ]
)
