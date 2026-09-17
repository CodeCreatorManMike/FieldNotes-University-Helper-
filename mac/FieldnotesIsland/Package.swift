// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FieldnotesIsland",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FieldnotesIsland",
            path: "Sources/FieldnotesIsland",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
