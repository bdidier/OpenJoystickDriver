/// Names one connected controller; an omitted command reads calibration status.
public struct ApplicationServiceMotionCalibrationArguments: Codable, Sendable {
  public let controller: ControllerReference
  public let command: RemappingMotionCalibrationCommand?

  public init(controller: ControllerReference, command: RemappingMotionCalibrationCommand? = nil) {
    self.controller = controller
    self.command = command
  }

  private enum CodingKeys: String, CodingKey {
    case controller
    case command
  }
}
