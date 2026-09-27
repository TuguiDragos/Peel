// swift-tools-version: 6.4
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
]

let package = Package(
    name: "PeelCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PeelCore", targets: ["PeelCore"]),
        .library(name: "PeelPrivileged", targets: ["PeelPrivileged"]),
        .library(name: "PeelCommandLine", targets: ["PeelCommandLine"]),
        .library(name: "PeelLink", targets: ["PeelLink"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
    ],
    targets: [
        .target(name: "PeelPrivileged", swiftSettings: swiftSettings),
        .target(name: "PeelLink", swiftSettings: swiftSettings),
        .target(name: "PeelCore", dependencies: ["PeelPrivileged"], swiftSettings: swiftSettings),
        .target(
            name: "PeelCommandLine",
            dependencies: ["PeelCore", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "PeelCoreTests",
            dependencies: ["PeelCore", "PeelPrivileged", "PeelCommandLine", "PeelLink"],
            swiftSettings: swiftSettings
        ),
    ]
)
