// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChatGPTMicroLaunchpad",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ChatGPTMicroLaunchpad", targets: ["ChatGPTMicroLaunchpad"])],
    targets: [
        .executableTarget(
            name: "ChatGPTMicroLaunchpad",
            path: "Native"
        ),
        .testTarget(
            name: "ChatGPTMicroLaunchpadTests",
            dependencies: ["ChatGPTMicroLaunchpad"],
            path: "Tests/ChatGPTMicroLaunchpadTests"
        )
    ]
)
