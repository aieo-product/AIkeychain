// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIkeychain",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AIkeychain",
            path: "AIkeychain",
            resources: [
                .process("Resources/Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "AIkeychainTests",
            dependencies: ["AIkeychain"],
            path: "Tests/AIkeychainTests"
        ),
    ]
)
