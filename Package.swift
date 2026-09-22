// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitHubMonitor",
    // macOS 26: the app uses the system's own glass materials rather than
    // reproducing them, and those exist from 26 on.
    platforms: [.macOS("26.0")],
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
