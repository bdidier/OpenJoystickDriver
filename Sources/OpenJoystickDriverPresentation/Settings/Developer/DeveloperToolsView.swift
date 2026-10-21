#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct DeveloperToolsView: View {
    @ObservedObject
    private var model: DeveloperToolsViewModel

    init(model: DeveloperToolsViewModel) { self.model = model }

    /// The pane's Settings window has a fixed width, so the content always uses the wide layout.
    /// The view does not scroll; the pane's form does.
    var body: some View {
      VStack(alignment: .leading, spacing: 20) {
        PageHeader(
          title: OJDLocalized.string("developer.title"),
          subtitle: OJDLocalized.string("developer.subtitle")
        )
        content(compact: false)
      }.frame(maxWidth: .infinity, alignment: .leading).onAppear { model.requestRefresh() }
        .onDisappear { model.close() }
    }

    @ViewBuilder
    private func content(compact: Bool) -> some View {
      switch model.loadState {
      case .idle, .loading:
        LoadingStateView(
          message: OJDLocalized.string(
            "developer.loadingControllers"
          )
        )
      case .noControllers:
        EmptyStateView(
          symbol: "gamecontroller",
          title: OJDLocalized.string(
            "developer.noControllers"
          ),
          message: OJDLocalized.string(
            "developer.noControllersDetail"
          )
        )
        Button(OJDLocalized.string("common.refresh")) {
          Task { @MainActor in await model.refresh() }
        }
      case .unavailable(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "developer.unavailable"
          ),
          message: message
        ) { Task { @MainActor in await model.refresh() } }
      case .ready:
        DeveloperControllerSummaryView(model: model, compact: compact)
        DeveloperPacketCaptureView(model: model)
        extraInputDiscovery
      }
    }

    private var extraInputDiscovery: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Text(
            OJDLocalized.string(
              "developer.extraInputsDescription"
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )

          if model.observedExtraInputs.isEmpty {
            Text(
              OJDLocalized.string("developer.noExtraInputs")
            ).foregroundColor(Color(NSColor.secondaryLabelColor))
          } else {
            Text(
              model.observedExtraInputs.map(InputTestButtonPresentation.localizedTitle)
                .joined(separator: ", ")
            ).textSelection(.enabled)
          }
        }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        Text(OJDLocalized.string("developer.extraInputs")).font(
          .headline
        )
      }
    }
  }

#endif
