// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "WebRTCBridge",
  platforms: [.macOS(.v12)],
  products: [.executable(name: "ojd-webrtc-bridge", targets: ["WebRTCBridge"])],
  dependencies: [
    .package(path: "../BridgeCore"),
    .package(url: "https://github.com/livekit/webrtc-xcframework.git", exact: "150.7871.03"),
  ],
  targets: [
    .target(
      name: "WebRTCBridgeCore",
      dependencies: [
        .product(name: "BridgeCore", package: "BridgeCore"),
        .product(name: "LiveKitWebRTC", package: "webrtc-xcframework"),
      ]
    ),
    .executableTarget(name: "WebRTCBridge", dependencies: ["WebRTCBridgeCore"]),
    .testTarget(
      name: "WebRTCBridgeCoreTests",
      dependencies: ["WebRTCBridgeCore", .product(name: "BridgeCore", package: "BridgeCore")]
    ),
  ]
)
