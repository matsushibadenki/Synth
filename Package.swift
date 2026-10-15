// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Synth",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SynthApp", targets: ["SynthApp"])
    ],
    targets: [
        .executableTarget(
            name: "SynthApp",
            path: "Sources/SynthApp"
        )
    ]
)
