// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vamp",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "VampCore"),
        .executableTarget(name: "Vamp", dependencies: ["VampCore"]),
        .testTarget(name: "VampCoreTests", dependencies: ["VampCore"]),
    ],
    swiftLanguageModes: [.v5]
)
