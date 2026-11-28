// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Theme", targets: ["Theme"]),
        .library(name: "Components", targets: ["Components"]),
    ],
    dependencies: [.package(path: "../TestSupport")],
    targets: [
        .target(name: "Theme"),
        .target(name: "Components", dependencies: ["Theme"], resources: [.process("Resources")]),
        .testTarget(name: "ThemeTests", dependencies: ["Theme", "TestSupport"]),
        .testTarget(name: "ComponentsTests", dependencies: ["Components", "Theme", "TestSupport"]),
    ]
)
