// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BackTrack",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BackTrack", targets: ["BackTrack"])
    ],
    targets: [
        .executableTarget(
            name: "BackTrack",
            path: "Sources/BackTrack"
        )
    ]
)
