// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitHubMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        // All logic and UI lives in the library so that it can be unit tested;
        // the executable is only a thin bootstrap.
        .target(
            name: "GitHubMonitorKit",
            path: "Sources/GitHubMonitorKit"
        ),
        .executableTarget(
            name: "GitHubMonitor",
            dependencies: ["GitHubMonitorKit"],
            path: "Sources/GitHubMonitor"
        ),
        .testTarget(
            name: "GitHubMonitorKitTests",
            dependencies: ["GitHubMonitorKit"],
            path: "Tests/GitHubMonitorKitTests"
        ),
    ]
)
