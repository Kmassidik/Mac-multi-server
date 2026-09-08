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
        // tiny C shim for openpty + TIOCSWINSZ (variadic ioctl isn't callable from Swift)
        .target(name: "CPTY"),
        .executableTarget(
            name: "Panel",
            dependencies: [.product(name: "Swifter", package: "swifter"), "CPTY"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // pure-function unit tests (no I/O, no network): `swift test`
        .testTarget(
            name: "PanelTests",
            dependencies: ["Panel"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
