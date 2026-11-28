// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TestSupport",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TestSupport", targets: ["TestSupport"])],
    targets: [.target(name: "TestSupport")]
)
