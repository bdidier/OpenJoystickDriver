import Foundation

let remappingStateNanosecondsPerMillisecond: Double = 1_000_000

struct RemappingEngineState {
  var devices: [LogicalControllerID: RemappingDeviceState] = [:]
  var keyReferences: [RemappingKeyboardKey: Int] = [:]
  var modifierReferences: [RemappingKeyModifier: Int] = [:]
  var mouseButtonReferences: [RemappingMouseButton: Int] = [:]
  /// The last snapshot each physical source delivered, which its next snapshot is diffed against.
  var sourceBaselines: [LogicalControllerID: ControllerState] = [:]
}
