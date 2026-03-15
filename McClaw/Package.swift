// swift-tools-version: 6.0
// McClaw - Native macOS AI Assistant (CLI Bridge Architecture)

import PackageDescription

let package = Package(
    name: "McClaw",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "McClaw", targets: ["McClaw"]),
        .library(name: "McClawKit", targets: ["McClawKit"]),
        .library(name: "McClawIPC", targets: ["McClawIPC"]),
    ],
    dependencies: [
        // Menu bar control
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess.git", from: "1.2.2"),
        // Structured logging
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        // Auto-updates
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.1"),
    ],
    targets: [
        // MARK: - Main App
        .executableTarget(
            name: "McClaw",
            dependencies: [
                "McClawKit",
                "McClawIPC",
                "MenuBarExtraAccess",
                .product(name: "Logging", package: "swift-log"),
                "Sparkle",
            ],
            path: "Sources/McClaw",
            resources: [
                .process("Resources"),
            ]
        ),

        // MARK: - Core Library
        .target(
            name: "McClawKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/McClawKit"
        ),

        // MARK: - IPC Protocol Library
        .target(
            name: "McClawIPC",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/McClawIPC"
        ),

        // MARK: - Tests
        .testTarget(
            name: "McClawTests",
            dependencies: ["McClawKit"],
            path: "Tests/McClawTests"
        ),
        .testTarget(
            name: "McClawKitTests",
            dependencies: ["McClawKit"],
            path: "Tests/McClawKitTests"
        ),
    ]
)
