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
            path: "Sources/SynthApp",
            // Audio must meet the device deadline when launched with Xcode Run,
            // too. Keep debug symbols, but optimize the per-sample Swift DSP.
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        )
    ]
)
