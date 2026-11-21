// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Velora",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VeloraCore",
            targets: ["VeloraCore"]
        ),
        .executable(
            name: "Velora",
            targets: ["Velora"]
        )
    ],
    targets: [
        .target(
            name: "VeloraCore",
            path: "Sources/VeloraCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "Velora",
            dependencies: ["VeloraCore"],
            path: "Sources/Velora",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "VeloraCoreTests",
            dependencies: ["VeloraCore"],
            path: "Tests/VeloraCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
