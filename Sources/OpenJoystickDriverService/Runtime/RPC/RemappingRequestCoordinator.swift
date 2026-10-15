import Foundation
import OpenJoystickDriverKit

typealias RemappingRequestResult<Value: Sendable> = Result<
  Value, ApplicationServiceRemappingRPCError
>

/// Serializes profile mutations, route refreshes, and the snapshot returned to RPC clients.
actor RemappingRequestCoordinator {
  typealias MutationResponseAcceptanceHook =
    @Sendable (ApplicationServiceRemappingSnapshotPayload) async throws -> Void

  let library: RemappingProfileLibrary
  let router: RemappingOutputRouter
  /// The connected controllers that controller references resolve against.
  let connectedControllers: @Sendable () async -> [ConnectedController]
  let postEventAccess: CoreGraphicsPostEventAccess
  let maximumResponseBytes: Int
  let maximumTransportFrameBytes: Int
  let beforeMutationResponseAcceptance: MutationResponseAcceptanceHook
  var operationTail: (id: UUID, task: Task<Void, Never>)?

  init(
    library: RemappingProfileLibrary,
    router: RemappingOutputRouter,
    connectedControllers: @escaping @Sendable () async -> [ConnectedController],
    postEventAccess: CoreGraphicsPostEventAccess,
    maximumResponseBytes: Int = ApplicationServiceRemappingRPC.maximumPayloadBytes,
    maximumTransportFrameBytes: Int = ApplicationServiceRemappingRPC.maximumTransportFrameBytes,
    beforeMutationResponseAcceptance: @escaping MutationResponseAcceptanceHook = { _ in }
  ) {
    self.library = library
    self.router = router
    self.connectedControllers = connectedControllers
    self.postEventAccess = postEventAccess
    self.maximumResponseBytes = maximumResponseBytes
    self.maximumTransportFrameBytes = maximumTransportFrameBytes
    self.beforeMutationResponseAcceptance = beforeMutationResponseAcceptance
  }
}
