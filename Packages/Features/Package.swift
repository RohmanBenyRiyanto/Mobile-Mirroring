// swift-tools-version:5.9
import PackageDescription

// The screens and the models behind them. Dependencies only point downwards; WorkspaceFeature, the main window,
// is the only one that knows the others.
let package = Package(
    name: "Features",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeymapFeature", targets: ["KeymapFeature"]),
        .library(name: "LogcatFeature", targets: ["LogcatFeature"]),
        .library(name: "InspectorFeature", targets: ["InspectorFeature"]),
        .library(name: "WorkspaceFeature", targets: ["WorkspaceFeature"]),
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../DesignSystem"),
        .package(path: "../TestSupport"),
    ],
    targets: [
        // Keyboard-to-touch mapping: the live controller and the editor (overlay and panel).
        .target(name: "KeymapFeature", dependencies: [
            .product(name: "DomainModels", package: "Core"), .product(name: "Persistence", package: "Core"),
            .product(name: "SystemServices", package: "Core"), .product(name: "Theme", package: "DesignSystem"),
        ]),
        // adb logcat for the app in front, with crash blocks.
        .target(name: "LogcatFeature", dependencies: [
            .product(name: "DomainModels", package: "Core"), .product(name: "Networking", package: "Core"),
            .product(name: "Theme", package: "DesignSystem"),
        ]),
        // UI inspector, grid, crosshair and colour picker.
        .target(name: "InspectorFeature", dependencies: [
            .product(name: "DomainModels", package: "Core"), .product(name: "Networking", package: "Core"),
            .product(name: "Theme", package: "DesignSystem"),
        ]),
        // The main window: connect screen, mirror, rail, menus, and the model that ties a phone together.
        .target(name: "WorkspaceFeature", dependencies: [
            .product(name: "DomainModels", package: "Core"), .product(name: "Persistence", package: "Core"),
            .product(name: "Media", package: "Core"), .product(name: "Networking", package: "Core"),
            .product(name: "SystemServices", package: "Core"), .product(name: "Theme", package: "DesignSystem"),
            "KeymapFeature", "LogcatFeature", "InspectorFeature",
        ]),

        // Test helper: a stand-in for the real pointer lock.
        .target(name: "FeatureTestSupport", dependencies: [.product(name: "SystemServices", package: "Core")]),

        .testTarget(name: "KeymapFeatureTests", dependencies: [
            "KeymapFeature", "FeatureTestSupport", .product(name: "DomainModels", package: "Core"), .product(name: "Persistence", package: "Core"), .product(name: "TestSupport", package: "TestSupport"),
        ]),
        .testTarget(name: "LogcatFeatureTests", dependencies: [
            "LogcatFeature", .product(name: "DomainModels", package: "Core"), .product(name: "TestSupport", package: "TestSupport"),
        ]),
        .testTarget(name: "InspectorFeatureTests", dependencies: [
            "InspectorFeature", .product(name: "DomainModels", package: "Core"), .product(name: "TestSupport", package: "TestSupport"),
        ]),
        .testTarget(name: "WorkspaceFeatureTests", dependencies: [
            "WorkspaceFeature", "KeymapFeature", "LogcatFeature", "InspectorFeature", "FeatureTestSupport",
            .product(name: "DomainModels", package: "Core"), .product(name: "Persistence", package: "Core"), .product(name: "Networking", package: "Core"), .product(name: "Media", package: "Core"), .product(name: "CoreTestSupport", package: "Core"), .product(name: "TestSupport", package: "TestSupport"),
        ]),
    ]
)
