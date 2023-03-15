// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "rigol2spice",
    platforms: [
        .macOS(.v10_11),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.1.0"),
        .package(url: "https://github.com/RuiNelson/Progress.swift", from: "0.5.0"),
        .package(url: "https://github.com/RuiNelson/SwiftEngineeringNumberFormatter", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "rigol2spice",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Progress", package: "Progress.swift"),
                .product(name: "SwiftEngineeringNumberFormatter", package: "SwiftEngineeringNumberFormatter"),
            ]
        ),
        .testTarget(
            name: "rigol2spiceTests",
            dependencies: ["rigol2spice"]
        ),
    ]
)
