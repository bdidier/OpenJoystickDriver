#if canImport(AppKit)

  import AppKit

  /// Applies the Show in Dock setting. One rule decides the policy: the app has a Dock icon
  /// (`.regular`) while Show in Dock is on or any window is open, and none (`.accessory`)
  /// otherwise.
  @MainActor
  final class DockIconController {
    enum Window: Hashable {
      case workbench
      case inputTest
      case settings
    }

    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Bool
    private var openWindows: Set<Window> = []
    /// The Show in Dock setting.
    var showsAlways = false {
      didSet { reconcile() }
    }
    private(set) var appliedPolicy = NSApplication.ActivationPolicy.accessory

    init(
      setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool = {
        NSApplication.shared.setActivationPolicy($0)
      }
    ) { self.setActivationPolicy = setActivationPolicy }

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
    }
  }

#endif
