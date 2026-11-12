// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YouTubeDownloader",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "YouTubeDownloader", targets: ["YouTubeDownloader"])
    ],
    targets: [
        .executableTarget(
            name: "YouTubeDownloader",
            path: "Sources/YTDownloader",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "YouTubeDownloaderTests", dependencies: ["YouTubeDownloader"])
    ]
)
