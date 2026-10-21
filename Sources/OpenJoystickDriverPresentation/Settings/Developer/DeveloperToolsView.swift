#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The form sections of the developer tools: Controller, Raw Packet Capture and Extra Buttons.
  /// They sit in the Advanced pane's form, which scrolls. The Settings window controller starts and
  /// stops the reads.
  struct DeveloperToolsView: View {
    @ObservedObject
    private var model: DeveloperToolsViewModel

    init(model: DeveloperToolsViewModel) { self.model = model }

    var body: some View {
      content
    }

    @ViewBuilder
    private var content: some View {
      switch model.loadState {
      case .idle:
        Section(OJDLocalized.string("developer.controllerDetails")) {
          Text(OJDLocalized.string("developer.notLoaded")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
          refreshButton
        }
      case .loading:
        Section {
          Text(OJDLocalized.string("developer.loadingControllers")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
      case .noControllers:
        Section(OJDLocalized.string("developer.controllerDetails")) {
          Text(OJDLocalized.string("developer.noControllers"))
          Text(OJDLocalized.string("developer.noControllersDetail")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
          refreshButton
        }
      case .unavailable(let message):
        Section(OJDLocalized.string("developer.controllerDetails")) {
          Text(OJDLocalized.string("developer.unavailable"))
          Text(message).foregroundColor(Color(NSColor.secondaryLabelColor))
          refreshButton
        }
      case .ready:
        DeveloperControllerSummaryView(model: model)
        DeveloperPacketCaptureView(model: model)
        extraInputDiscovery
      }
    }

    private var refreshButton: some View {
      Button(OJDLocalized.string("common.refresh")) {
        Task { @MainActor in await model.refresh() }
      }
    }

    private var extraInputDiscovery: some View {
      Section(OJDLocalized.string("developer.extraInputs")) {
        Text(OJDLocalized.string("developer.extraInputsDescription")).font(.caption)
          .foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        if model.observedExtraInputs.isEmpty {
          Text(OJDLocalized.string("developer.noExtraInputs")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        } else {
          Text(
            model.observedExtraInputs.map(InputTestButtonPresentation.localizedTitle)
              .joined(separator: ", ")
          ).textSelection(.enabled)
        }
      }
    }
  }

#endif
