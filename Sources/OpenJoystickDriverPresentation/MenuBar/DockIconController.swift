#if canImport(AppKit)

  import AppKit

  /// Applies the Show in Dock setting. One rule decides the policy: the app has a Dock icon
  /// (`.regular`) while Show in Dock is on or any window is open, and none (`.accessory`)
  /// otherwise.
  ///
  /// An accessory app that becomes regular because a window opened is not yet the active
  /// application of the new policy: its menu bar shows, but AppKit does not track its menus until
  /// the app is activated once more after the policy took effect. The controller therefore
  /// activates the app after every switch to `.regular` that a window caused.
  @MainActor
  final class DockIconController {
    enum Window: Hashable {
      case workbench
      case inputTest
      case settings
    }

    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Bool
    private let activateApplication: () -> Void
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
      activateApplication: @escaping () -> Void = {
        // The policy change completes on the next run loop turn; activating before it
        // leaves the menu bar untracked.
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
      }
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
  }

#endif
