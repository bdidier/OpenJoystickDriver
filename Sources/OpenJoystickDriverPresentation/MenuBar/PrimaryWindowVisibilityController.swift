#if canImport(AppKit)

  import AppKit

  @MainActor
  final class PrimaryWindowVisibilityController {
    enum Window: Hashable {
      case workbench
      case inputTest
      case settings
    }

    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Bool
    private var openWindows: Set<Window> = []
    /// True while the status item is hidden: the Dock icon is then the only way back into the
    /// app, so the policy stays `.regular` with every window closed.
    var keepsDockIcon = false {
      didSet { reconcileActivationPolicy() }
    }
    private(set) var appliedPolicy = NSApplication.ActivationPolicy.accessory

    init(
      setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool = {
        NSApplication.shared.setActivationPolicy($0)
      }
    ) { self.setActivationPolicy = setActivationPolicy }

    func opened(_ window: Window) {
      openWindows.insert(window)
      reconcileActivationPolicy()
    }

    func closed(_ window: Window) {
      openWindows.remove(window)
      reconcileActivationPolicy()
    }

    func isOpen(_ window: Window) -> Bool { openWindows.contains(window) }

    private func reconcileActivationPolicy() {
      let desiredPolicy: NSApplication.ActivationPolicy =
        openWindows.isEmpty && !keepsDockIcon ? .accessory : .regular
      guard desiredPolicy != appliedPolicy, setActivationPolicy(desiredPolicy) else { return }
      appliedPolicy = desiredPolicy
    }
  }

#endif
