// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EdgeVeda",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "EdgeVeda", targets: ["EdgeVeda"]),
    ],
    targets: [
        .target(
            name: "EdgeVeda",
            dependencies: ["CEdgeVeda"],
            path: "Sources/EdgeVeda"
        ),
        .systemLibrary(
            name: "CEdgeVeda",
            path: "Sources/CEdgeVeda"
        ),
        .testTarget(
            name: "EdgeVedaTests",
            dependencies: ["EdgeVeda"],
            path: "Tests/EdgeVedaTests"
        ),
    ]
)
