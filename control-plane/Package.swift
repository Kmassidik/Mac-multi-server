// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macserver-panel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "macserver-panel", targets: ["Panel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "Panel",
            dependencies: [.product(name: "Swifter", package: "swifter")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
