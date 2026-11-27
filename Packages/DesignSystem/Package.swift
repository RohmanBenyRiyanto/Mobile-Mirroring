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
        // Colours, type, spacing and the surfaces everything is drawn on (glass on macOS 26+, materials before).
        .target(name: "Theme"),
        // Reusable pieces built from the tokens: cards, rows, preset cards, numbered steps.
        .target(name: "Components", dependencies: ["Theme"], resources: [.process("Resources")]),
        .testTarget(name: "ThemeTests", dependencies: ["Theme", "TestSupport"]),
        .testTarget(name: "ComponentsTests", dependencies: ["Components", "Theme", "TestSupport"]),
    ]
)
