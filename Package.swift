// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Untyped",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Untyped",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "UntypedTests",
            dependencies: ["Untyped"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
