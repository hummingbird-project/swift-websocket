// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency=complete")]

let package = Package(
    name: "swift-websocket",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16)],
    products: [
        .library(name: "WSClient", targets: ["WSClient"]),
        .library(name: "WSCompression", targets: ["WSCompression"]),
        .library(name: "WSCore", targets: ["WSCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.93.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.31.3"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.5.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0"),
        .package(url: "https://github.com/adam-fowler/compress-nio.git", from: "1.3.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "WSClient",
            dependencies: [
                .byName(name: "WSCore"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTPTypesHTTP1", package: "swift-nio-extras"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSOCKS", package: "swift-nio-extras"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "WSCore",
            dependencies: [
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "WSCompression",
            dependencies: [
                .byName(name: "WSCore"),
                .product(name: "CompressNIO", package: "compress-nio"),
            ],
            swiftSettings: swiftSettings
        ),

        .testTarget(
            name: "WebSocketTests",
            dependencies: [
                .byName(name: "WSClient"),
                .byName(name: "WSCompression"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5, .version("6")]
)
