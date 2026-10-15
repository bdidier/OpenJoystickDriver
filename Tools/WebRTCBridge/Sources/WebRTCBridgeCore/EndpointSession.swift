import CryptoKit
import Darwin
import Foundation

public let endpointAPIVersion = "openjoystickdriver/v1alpha1"

public enum BridgeError: Error, CustomStringConvertible, Equatable {
  case socket(String)
  case endpoint(code: String, message: String)
  case protocolViolation(String)
  case signaling(String)

  public var description: String {
    switch self {
    case .socket(let text), .protocolViolation(let text), .signaling(let text): return text
    case .endpoint(let code, let message): return "\(code): \(message)"
    }
  }
}

/// A connection to the SDK endpoint's Unix socket after the Challenge, Hello and Welcome lines.
///
/// The session follows `docs/sdk/endpoint.md`: one JSON object per line, a token proof over the
/// challenge, and one request (`Subscription` or `FeedRequest`) after the `Welcome`.
public final class EndpointSession: @unchecked Sendable {
  public typealias Line = [String: Any]

  private let descriptor: Int32
  private var buffer = Data()
  private let writeLock = NSLock()

  private init(descriptor: Int32) { self.descriptor = descriptor }

  deinit { Darwin.close(descriptor) }

  /// The proof for a token: HMAC-SHA256 of the four hello lines, keyed with SHA-256 of the token.
  public static func proof(token: String, nonce: String) -> String {
    let message = ["OpenJoystickDriver endpoint hello 1", nonce, "", ""].map { $0 + "\n" }.joined()
    let key = SymmetricKey(data: SHA256.hash(data: Data(token.utf8)))
    let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
    return code.map { String(format: "%02x", $0) }.joined()
  }

  public static func connect(
    socketPath: String,
    token: String,
    tokenName: String,
    scopes: [String]
  ) throws -> EndpointSession {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw BridgeError.socket("socket() failed: errno \(errno)") }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard socketPath.utf8.count < capacity else {
      Darwin.close(descriptor)
      throw BridgeError.socket("The socket path is too long.")
    }
    withUnsafeMutableBytes(of: &address.sun_path) { target in
      target.copyBytes(from: socketPath.utf8)
    }
    let status = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard status == 0 else {
      Darwin.close(descriptor)
      throw BridgeError.socket("Cannot connect to \(socketPath): errno \(errno)")
    }
    var noSigPipe: Int32 = 1
    setsockopt(
      descriptor,
      SOL_SOCKET,
      SO_NOSIGPIPE,
      &noSigPipe,
      socklen_t(MemoryLayout<Int32>.size)
    )
    let session = EndpointSession(descriptor: descriptor)
    try session.handshake(token: token, tokenName: tokenName, scopes: scopes)
    return session
  }

  private func handshake(token: String, tokenName: String, scopes: [String]) throws {
    guard let challenge = try readLine(), challenge["kind"] as? String == "Challenge",
      let nonce = challenge["nonce"] as? String
    else { throw BridgeError.protocolViolation("The endpoint did not send a Challenge.") }
    try send([
      "apiVersion": endpointAPIVersion, "kind": "Hello", "scopes": scopes,
      "tokenName": tokenName, "proof": Self.proof(token: token, nonce: nonce),
    ])
    guard let welcome = try readLine(), welcome["kind"] as? String == "Welcome" else {
      throw BridgeError.protocolViolation("The endpoint did not send a Welcome.")
    }
  }

  public func send(_ line: Line) throws {
    var data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
    data.append(0x0A)
    writeLock.lock()
    defer { writeLock.unlock() }
    var offset = 0
    while offset < data.count {
      let written = data.withUnsafeBytes {
        Darwin.write(descriptor, $0.baseAddress! + offset, data.count - offset)
      }
      guard written > 0 else { throw BridgeError.socket("Write failed: errno \(errno)") }
      offset += written
    }
  }

  /// Blocks for the next line. Returns nil when the endpoint closed the connection. A `Status`
  /// failure throws its error code.
  public func readLine() throws -> Line? {
    while true {
      if let newline = buffer.firstIndex(of: 0x0A) {
        let text = Data(buffer[buffer.startIndex..<newline])
        buffer.removeSubrange(buffer.startIndex...newline)
        guard let object = try JSONSerialization.jsonObject(with: text) as? Line else {
          throw BridgeError.protocolViolation("The endpoint sent a line that is not an object.")
        }
        if object["kind"] as? String == "Status", object["status"] as? String == "Failure" {
          throw BridgeError.endpoint(
            code: object["code"] as? String ?? "unknown",
            message: object["message"] as? String ?? ""
          )
        }
        return object
      }
      var chunk = [UInt8](repeating: 0, count: 16 * 1024)
      let count = Darwin.read(descriptor, &chunk, chunk.count)
      if count < 0 && errno == EINTR { continue }
      guard count > 0 else { return nil }
      buffer.append(contentsOf: chunk[0..<count])
    }
  }

  /// Ends the connection and wakes a blocked `readLine`.
  public func close() { Darwin.shutdown(descriptor, SHUT_RDWR) }
}
