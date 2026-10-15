// swift-tools-version: 5.9
import PackageDescription

// The endpoint client and the bridge logic of the WebRTC bridge, with no WebRTC dependency, so
// that the root package's tests can drive them against a real `EndpointServer`.
let package = Package(
  name: "BridgeCore",
  platforms: [.macOS(.v12)],
  products: [.library(name: "BridgeCore", targets: ["BridgeCore"])],
  targets: [.target(name: "BridgeCore")]
)
