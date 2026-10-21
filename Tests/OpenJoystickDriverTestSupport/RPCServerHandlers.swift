import OpenJoystickDriverKit

/// Adapts a test handler that answers through a completion closure to the server's async
/// handler. The body calls `completion` exactly once; it may do so after the body returns.
package func completionHandler(
  _ body:
    @escaping @Sendable (
      LocalServiceRPCRequest, @escaping @Sendable (LocalServiceRPCResponse) -> Void
    ) -> Void
) -> LocalServiceRPCServer.Handler {
  { request in
    await withCheckedContinuation { continuation in
      body(request) { continuation.resume(returning: $0) }
    }
  }
}
