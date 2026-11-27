// swift-tools-version:5.9
import PackageDescription

// Helpers shared by the tests of every package: drawing a SwiftUI view to an image, and running Homebrew tools
// (ffmpeg, ffprobe). Only test targets depend on this.
let package = Package(
    name: "TestSupport",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TestSupport", targets: ["TestSupport"])],
    targets: [.target(name: "TestSupport")]
)
