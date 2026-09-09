// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TypelessLike",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "TypelessLike",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TypelessLikeTests",
            dependencies: ["TypelessLike"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
