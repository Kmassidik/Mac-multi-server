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
        // pure, I/O-free helpers — a library so they're testable without Xcode
        .target(name: "PanelCore"),
        .executableTarget(
            name: "Panel",
            dependencies: [.product(name: "Swifter", package: "swifter"), "CPTY", "PanelCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // dependency-free unit checks (no XCTest, runs on Command-Line-Tools only): `swift run pcheck`
        .executableTarget(
            name: "pcheck",
            dependencies: ["PanelCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
