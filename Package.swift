// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "rigol2spice",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.5.0"),
        .package(url: "https://github.com/RuiNelson/SwiftEngineeringNumberFormatter", exact: "3.0.1"),
    ],
    targets: [
        .executableTarget(
            name: "rigol2spice",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftEngineeringNumberFormatter", package: "SwiftEngineeringNumberFormatter"),
            ],
        ),
        .testTarget(
            name: "rigol2spiceTests",
            dependencies: ["rigol2spice"],
            resources: [
                .copy("SampleFiles"),
            ],
        ),
    ],
)
