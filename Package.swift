// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BackTrack",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .executable(name: "BackTrack", targets: ["BackTrackMac"]),
        .library(name: "BackTrackCore", targets: ["BackTrackCore"]),
        .library(name: "BackTrackPadKit", targets: ["BackTrackPadKit"]),
    ],
    targets: [
        .target(
            name: "BackTrackCore",
            path: "Sources/BackTrackCore"
        ),
        .executableTarget(
            name: "BackTrackMac",
            dependencies: ["BackTrackCore"],
            path: "Sources/BackTrackMac"
        ),
        .target(
            name: "BackTrackPadKit",
            dependencies: ["BackTrackCore"],
            path: "Sources/BackTrackPadKit"
        ),
        .testTarget(
            name: "BackTrackTests",
            dependencies: ["BackTrackCore"],
            path: "Tests/BackTrackTests"
        ),
    ]
)
