import Darwin
import Foundation
import BridgeCore
import WebRTCBridgeCore

/// A stand-in endpoint on a Unix socket. It speaks the handshake of `docs/sdk/endpoint.md`,
/// checks the token proof, and then runs one scripted connection. It stops listening after the
/// last expected connection, so a socket scan sees only the bridges.
final class FakeEndpoint: @unchecked Sendable {
  static let token = "ojd_test_token"
  static let tokenName = "bridge"

  let path: String
  private var listener: Int32 = -1
  private let lock = NSLock()
  private(set) var framesReceived: [[String: Any]] = []
  private(set) var requests: [[String: Any]] = []
  private(set) var proofsValid: [Bool] = []
  private var keepAlives = 0
  let watchLines: [[String: Any]]
  let rumble: [String: Any]
  /// Lines that a feed gets right after its `FeedSession`.
  let feedLines: [[String: Any]]

  init(
    watchLines: [[String: Any]] = [],
    rumble: [String: Any] = [:],
    feedLines: [[String: Any]] = []
  ) throws {
    self.watchLines = watchLines
    self.feedLines = feedLines
    self.rumble = rumble
    path = "/tmp/ojd-bridge-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock"
    listener = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bound == 0, Darwin.listen(listener, 4) == 0 else { throw BridgeError.socket("bind") }
  }

  /// Serves `count` connections on background threads, then closes the listening socket.
  func serve(connections count: Int) {
    let listener = listener
    Thread.detachNewThread { [self] in
      for _ in 0..<count {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { break }
        Thread.detachNewThread { self.handle(client) }
      }
      Darwin.close(listener)
      unlink(path)
    }
  }

  private func record(_ body: () -> Void) {
    lock.lock()
    body()
    lock.unlock()
  }

  func snapshot() -> (frames: [[String: Any]], requests: [[String: Any]], proofs: [Bool]) {
    lock.lock()
    defer { lock.unlock() }
    return (framesReceived, requests, proofsValid)
  }

  /// The `KeepAlive` lines that the feed received.
  func keepAliveCount() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return keepAlives
  }

  private func write(_ client: Int32, _ line: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: line) else { return }
    data.append(0x0A)
    _ = data.withUnsafeBytes { Darwin.write(client, $0.baseAddress!, data.count) }
  }

  private func handle(_ client: Int32) {
    var pending = Data()
    func next() -> [String: Any]? {
      while true {
        if let newline = pending.firstIndex(of: 0x0A) {
          let text = Data(pending[pending.startIndex..<newline])
          pending.removeSubrange(pending.startIndex...newline)
          return (try? JSONSerialization.jsonObject(with: text)) as? [String: Any]
        }
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(client, &chunk, chunk.count)
        if count <= 0 { return nil }
        pending.append(contentsOf: chunk[0..<count])
      }
    }
    let nonce = "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8"
    write(client, ["apiVersion": endpointAPIVersion, "kind": "Challenge", "nonce": nonce])
    guard let hello = next(), hello["kind"] as? String == "Hello" else { return }
    let valid =
      hello["proof"] as? String == EndpointSession.proof(token: Self.token, nonce: nonce)
      && hello["tokenName"] as? String == Self.tokenName
    record { proofsValid.append(valid) }
    guard valid else {
      write(
        client,
        [
          "apiVersion": endpointAPIVersion, "kind": "Status", "status": "Failure",
          "code": "E1002", "message": "Not granted.",
        ]
      )
      return
    }
    write(
      client,
      [
        "apiVersion": endpointAPIVersion, "kind": "Welcome", "version": "test",
        "scopes": hello["scopes"] ?? [],
      ]
    )
    guard let request = next() else { return }
    record { requests.append(request) }
    switch request["kind"] as? String {
    case "Subscription":
      for line in watchLines { write(client, line) }
    case "FeedRequest":
      write(
        client,
        [
          "apiVersion": endpointAPIVersion, "kind": "FeedSession",
          "as": request["as"] ?? "Generic",
        ]
      )
      for line in feedLines { write(client, line) }
      var sentRumble = false
      while let line = next() {
        if line["kind"] as? String == "KeepAlive" {
          record { keepAlives += 1 }
          continue
        }
        guard line["kind"] as? String == "Frame" else { continue }
        record { framesReceived.append(line) }
        if !sentRumble && (line["buttons"] as? [String])?.isEmpty == false {
          sentRumble = true
          write(client, rumble)
        }
      }
    default: break
    }
    // Keep a subscription open until the bridge goes away.
    while next() != nil {}
    Darwin.close(client)
  }
}
