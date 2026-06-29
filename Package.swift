// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DarkbloomMenu",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DarkbloomCore"),
        .target(name: "DarkbloomMenuSupport"),
        .executableTarget(
            name: "DarkbloomMenu",
            dependencies: ["DarkbloomCore", "DarkbloomMenuSupport"]
        ),
        .testTarget(
            name: "DarkbloomCoreTests",
            dependencies: ["DarkbloomCore"]
        ),
        .testTarget(
            name: "DarkbloomMenuSupportTests",
            dependencies: ["DarkbloomMenuSupport"]
        ),
    ]
)
