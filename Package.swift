// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "rigol2spice",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.5.0")),
        .package(
            url: "https://github.com/RuiNelson/SwiftEngineeringNumberFormatter",
            .upToNextMajor(from: "3.0.1"),
        ),
        .package(url: "https://github.com/weichsel/ZIPFoundation", exact: "0.9.20"),
    ],
    targets: [
        .executableTarget(
            name: "rigol2spice",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftEngineeringNumberFormatter", package: "SwiftEngineeringNumberFormatter"),
                .product(
                    name: "ZIPFoundation",
                    package: "ZIPFoundation",
                    condition: .when(platforms: [.macOS, .linux]),
                ),
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
