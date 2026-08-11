// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vimkin",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Vimkin",
            path: "Sources/Vimkin",
            resources: [.copy("Content")]
        ),
        .testTarget(
            name: "VimkinTests",
            dependencies: ["Vimkin"],
            path: "Tests/VimkinTests"
        ),
    ]
)
