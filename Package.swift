// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DarkbloomMenu",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DarkbloomMenu",
            path: "Sources/DarkbloomMenu"
        )
    ]
)
