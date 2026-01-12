// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoSpaceship",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "VideoSpaceship",
            targets: ["VideoSpaceship"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "VideoSpaceship",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "VideoSpaceship",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "VideoSpaceshipTests",
            dependencies: ["VideoSpaceship"]
        )
    ]
)
