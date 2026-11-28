// swift-tools-version:5.9
import PackageDescription

// Everything below the screens: what a phone is, how to talk to it, how its picture and sound are handled.
// Dependencies only point downwards: Networking → Media → DomainModels → Persistence.
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
        // gRPC to the profiler daemon that Android Studio also uses, to see inside debuggable apps (HTTPS included).
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.24.2"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        // Generic, versioned profile files (keymaps today). No knowledge of what is stored.
        .target(name: "Persistence"),
        // Pure models, parsers and logic: settings, control messages, keymaps and their engine, log parsing, UI dumps.
        .target(name: "DomainModels", dependencies: ["Persistence"]),
        // Video decoding, audio playback, MP4 recording, MPEG-TS muxing and AAC encoding.
        .target(name: "Media", dependencies: ["DomainModels"]),
        // adb, the scrcpy session, sockets, wireless setup and the local OBS server.
        .target(name: "Networking", dependencies: ["DomainModels", "Media"]),
        // Looks inside a debuggable app through Android Studio's transport daemon and network inspector: HTTP and HTTPS calls with headers and bodies.
        .target(name: "AppInspection", dependencies: ["DomainModels", "Networking",
                                                     .product(name: "GRPC", package: "grpc-swift"),
                                                     .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                                                     .product(name: "NIOCore", package: "swift-nio"),
                                                     .product(name: "NIOPosix", package: "swift-nio")],
                exclude: ["Protos"]),
        // macOS facilities: pointer lock, key capture.
        .target(name: "SystemServices", dependencies: ["DomainModels"]),
        // Test helpers shared by the tests below (loopback client, ffmpeg-made test video).
        .target(name: "CoreTestSupport", dependencies: ["DomainModels", "Media", "Networking", "TestSupport"]),

        .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "TestSupport"]),
        .testTarget(name: "DomainModelsTests", dependencies: ["DomainModels", "Persistence", "TestSupport"]),
        .testTarget(name: "MediaTests", dependencies: ["Media", "DomainModels", "CoreTestSupport", "TestSupport"]),
        .testTarget(name: "AppInspectionTests", dependencies: ["AppInspection", "DomainModels", "Networking", "TestSupport"]),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking", "Media", "DomainModels", "CoreTestSupport", "TestSupport"]),
    ]
)
