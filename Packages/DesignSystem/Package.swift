// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Theme", targets: ["Theme"]),
    ],
    dependencies: [.package(path: "../TestSupport")],
    targets: [
        // Colours, type, spacing and the surfaces everything is drawn on (glass on macOS 26+, materials before).
        .target(name: "Theme"),
        .testTarget(name: "ThemeTests", dependencies: ["Theme", "TestSupport"]),
    ]
)
