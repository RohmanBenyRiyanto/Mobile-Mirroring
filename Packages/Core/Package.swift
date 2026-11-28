// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DomainModels", targets: ["DomainModels"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Media", targets: ["Media"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "AppInspection", targets: ["AppInspection"]),
        .library(name: "SystemServices", targets: ["SystemServices"]),
        .library(name: "CoreTestSupport", targets: ["CoreTestSupport"]),
    ],
    dependencies: [
        .package(path: "../TestSupport"),
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.24.2"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .target(name: "Persistence"),
        .target(name: "DomainModels", dependencies: ["Persistence"]),
        .target(name: "Media", dependencies: ["DomainModels"]),
        .target(name: "Networking", dependencies: ["DomainModels", "Media"]),
        .target(name: "AppInspection", dependencies: ["DomainModels", "Networking",
                                                     .product(name: "GRPC", package: "grpc-swift"),
                                                     .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                                                     .product(name: "NIOCore", package: "swift-nio"),
                                                     .product(name: "NIOPosix", package: "swift-nio")],
                exclude: ["Protos"]),
        .target(name: "SystemServices", dependencies: ["DomainModels"]),
        .target(name: "CoreTestSupport", dependencies: ["DomainModels", "Media", "Networking", "TestSupport"]),

        .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "TestSupport"]),
        .testTarget(name: "DomainModelsTests", dependencies: ["DomainModels", "Persistence", "TestSupport"]),
        .testTarget(name: "MediaTests", dependencies: ["Media", "DomainModels", "CoreTestSupport", "TestSupport"]),
        .testTarget(name: "AppInspectionTests", dependencies: ["AppInspection", "DomainModels", "Networking", "TestSupport"]),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking", "Media", "DomainModels", "CoreTestSupport", "TestSupport"]),
    ]
)
