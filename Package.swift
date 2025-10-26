// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "StarBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "StarBar", targets: ["StarBarApp"])
    ],
    targets: [
        .target(
            name: "StarBar"
        ),
        .executableTarget(
            name: "StarBarApp",
            dependencies: ["StarBar"]
        ),
        .testTarget(
            name: "StarBarTests",
            dependencies: ["StarBar"]
        ),
    ]
)
