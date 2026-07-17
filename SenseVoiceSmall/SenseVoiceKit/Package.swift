// swift-tools-version: 5.9
import PackageDescription

let package = Package(
        name: "SenseVoiceKit",
        platforms: [.macOS(.v13)],
        products: [
                .library(name: "SenseVoiceKit", targets: ["SenseVoiceKit"]),
                .executable(name: "sensevoice-cli", targets: ["sensevoice-cli"]),
        ],
        targets: [
                .target(name: "SenseVoiceKit"),
                .executableTarget(
                        name: "sensevoice-cli",
                        dependencies: ["SenseVoiceKit"]
                ),
        ]
)
