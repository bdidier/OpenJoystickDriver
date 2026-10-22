#if canImport(AppIntents)
  import AppIntents
  import Foundation
  import OpenJoystickDriverKit
  import OpenJoystickDriverService

  /// The Shortcuts action that returns the connected controllers.
  @available(macOS 13, *)
  struct GetControllersIntent: AppIntent {
    static let title = LocalizedStringResource(
      "ui.shortcuts.action.getControllers.title"
    )
    static let description = IntentDescription(
      LocalizedStringResource(
        "ui.shortcuts.action.getControllers.description"
      )
    )

    @Dependency
    var service: any AutomationService

    func perform() async -> some IntentResult & ReturnsValue<[ControllerEntity]> {
      // Only the controllers themselves; the model entries are for picking a controller.
      let controllers = await service.controllers().filter { !$0.isModelMatch }
      return .result(value: controllers.map(ControllerEntity.init))
    }
  }

  /// The Shortcuts action that returns the battery charge of one controller in percent.
  @available(macOS 13, *)
  struct GetBatteryLevelIntent: AppIntent {
    static let title = LocalizedStringResource(
      "ui.shortcuts.action.batteryLevel.title"
    )
    static let description = IntentDescription(
      LocalizedStringResource(
        "ui.shortcuts.action.batteryLevel.description"
      )
    )

    @Parameter(
      title: LocalizedStringResource("ui.shortcuts.parameter.controller")
    )
    var controller: ControllerEntity

    @Dependency
    var service: any AutomationService

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
      // Read the charge now; the entity Shortcuts passes in can be older than the last report.
      let current = try await service.controllers(ids: [controller.id]).first
      guard let battery = current?.battery else {
        throw BatteryLevelUnknownError(controller: current?.name ?? controller.name)
      }
      return .result(value: Int(battery.lowerBound))
    }
  }

  /// The controller reports no battery level, or is no longer connected.
  struct BatteryLevelUnknownError: Error, LocalizedError {
    let controller: String

    var errorDescription: String? {
      Localization().formatted(
        "ui.shortcuts.error.batteryUnknown",
        arguments: [controller]
      )
    }
  }
#endif
