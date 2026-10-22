#if canImport(AppKit)

  import AppKit

  /// Applies the Show in Dock setting. One rule decides the policy: the app has a Dock icon
  /// (`.regular`) while Show in Dock is on or any window is open, and none (`.accessory`)
  /// otherwise.
  ///
  /// An accessory app that becomes regular because a window opened is not yet the active
  /// application of the new policy: its menu bar shows, but AppKit does not track its menus until
  /// the app is activated again after another app was active. Activating an app that is already
  /// active does nothing, so after every switch to `.regular` that a window caused, the
  /// controller hands activation to the Dock and takes it back once the app resigned active.
  @MainActor
  final class DockIconController {
    enum Window: Hashable {
      case workbench
      case inputTest
      case settings
    }

    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Bool
    private let activateApplication: @MainActor () -> Void
    private var openWindows: Set<Window> = []
    /// The Show in Dock setting.
    var showsAlways = false {
      didSet { reconcile() }
    }
    private(set) var appliedPolicy = NSApplication.ActivationPolicy.accessory

    init(
      setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool = {
        NSApplication.shared.setActivationPolicy($0)
      },
      activateApplication: @escaping @MainActor () -> Void = DockIconController
        .reactivateThroughDock
    ) {
      self.setActivationPolicy = setActivationPolicy
      self.activateApplication = activateApplication
    }

    func setOpen(_ window: Window, _ isOpen: Bool) {
      if isOpen { openWindows.insert(window) } else { openWindows.remove(window) }
      reconcile()
    }

    /// When macOS refuses the change, the applied policy stays as it was, the refusal goes to
    /// standard error, and the next setting or window change tries again.
    private func reconcile() {
      let desiredPolicy: NSApplication.ActivationPolicy =
        showsAlways || !openWindows.isEmpty ? .regular : .accessory
      guard desiredPolicy != appliedPolicy else { return }
      guard setActivationPolicy(desiredPolicy) else {
        fputs(
          "macOS refused the Dock icon change to \(desiredPolicy); "
            + "the next window or setting change retries it.\n",
          stderr
        )
        return
      }
      appliedPolicy = desiredPolicy
      if desiredPolicy == .regular && !openWindows.isEmpty { activateApplication() }
    }

    private static func reactivateThroughDock() {
      guard
        let dock = NSRunningApplication.runningApplications(
          withBundleIdentifier: "com.apple.dock"
        ).first
      else {
        fputs(
          "The Dock is not running; the menu bar opens after the app is activated again.\n",
          stderr
        )
        return
      }
      guard resignObserver == nil else { return }
      resignObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didResignActiveNotification,
        object: nil,
        queue: .main
      ) { _ in
        MainActor.assumeIsolated {
          if let observer = resignObserver { NotificationCenter.default.removeObserver(observer) }
          resignObserver = nil
          NSApplication.shared.activate(ignoringOtherApps: true)
        }
      }
      dock.activate(options: [])
    }

    /// The one-shot observer that activates the app again after it handed activation to the Dock.
    private static var resignObserver: NSObjectProtocol?
  }

#endif
