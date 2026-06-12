// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DarkbloomMenu",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DarkbloomCore"),
        .executableTarget(
            name: "DarkbloomMenu",
            dependencies: ["DarkbloomCore"]
        ),
        .testTarget(
            name: "DarkbloomCoreTests",
            dependencies: ["DarkbloomCore"]
        ),
    ]
)
