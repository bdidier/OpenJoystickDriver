#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension MainWindowArea {
    var title: String { OJDLocalized.string(titleKey) }
    var accessibilityLabel: String { OJDLocalized.string(accessibilityKey) }
  }

  /// The models each area's screen reads. One instance lives as long as the main window.
  @MainActor
  struct MainWindowScreens {
    let runtime: RuntimeViewModel
    let supportReport: SupportReportModel
    let controllers: ControllersViewModel
    let library: ProfileLibraryModel
    let profiles: ProfilesViewModel
    let console: ConsoleViewModel
    let libraryArea: LibraryViewModel
    let access: AccessViewModel
    let restartApplication: @MainActor () -> Void
    let openInputTest: @MainActor (ApplicationServiceDeviceDescription) -> Void
  }

  struct MainWindowSidebar: View {
    @ObservedObject
    var navigation: MainWindowNavigationModel

    var body: some View {
      List(selection: selection) {
        ForEach(MainWindowArea.allCases) { area in
          HStack(spacing: 8) {
            OJDSystemSymbol(name: area.symbolName, fallback: nil).frame(width: 18)
              .accessibilityHidden(true)
            Text(area.title)
            Spacer(minLength: 0)
          }.padding(.vertical, 3).tag(area).ojdAccessibilityLabel(area.accessibilityLabel)
        }
      }.listStyle(SidebarListStyle()).frame(minWidth: 170, idealWidth: 190, maxWidth: 240)
        .ojdAccessibilityLabel(OJDLocalized.string("a11y.mainWindow.sidebar"))
    }

    private var selection: Binding<MainWindowArea?> {
      Binding(
        get: { navigation.selectedArea },
        set: { area in if let area { navigation.requestArea(area) } }
      )
    }
  }

  struct MainWindowDetail: View {
    @ObservedObject
    var navigation: MainWindowNavigationModel
    @ObservedObject
    var runtime: RuntimeViewModel
    @ObservedObject
    var profiles: ProfilesViewModel
    let screens: MainWindowScreens

    var body: some View {
      area.id(navigation.selectedArea).frame(
        maxWidth: .infinity,
        minHeight: 0,
        maxHeight: .infinity
      ).background(Color(NSColor.windowBackgroundColor)).onAppear { refreshIfNeeded() }.background(
        Color.clear.alert(isPresented: $navigation.isMutationRefusalPresented) {
          Alert(
            title: Text(OJDLocalized.string("mainWindow.profileMutationRunning")),
            dismissButton: .default(Text(OJDLocalized.string("common.ok")))
          )
        }
      ).alert(
        isPresented: $navigation.isDiscardConfirmationPresented
      ) {
        Alert(
          title: Text(OJDLocalized.string("settings.discardTitle")),
          message: Text(OJDLocalized.string("settings.discardProfileMessage")),
          primaryButton: .destructive(Text(OJDLocalized.string("settings.discardAction"))) {
            navigation.discardPendingArea()
          },
          secondaryButton: .cancel { navigation.cancelPendingArea() }
        )
      }
    }

    @ViewBuilder
    private var area: some View {
      switch navigation.selectedArea {
      case .status:
        OverviewView(
          viewModel: runtime,
          supportReport: screens.supportReport,
          navigation: navigation
        )
      case .controllers:
        ControllersView(screen: screens.controllers, openInputTest: screens.openInputTest)
      case .profiles:
        ProfilesView(
          viewModel: runtime,
          library: screens.library,
          navigation: navigation,
          screen: profiles
        )
      case .library: LibraryAreaView(runtime: runtime, model: screens.libraryArea)
      case .access:
        AccessAreaView(
          runtime: runtime,
          model: screens.access,
          restartApplication: screens.restartApplication
        )
      case .activity: ConsoleView(model: screens.console)
      }
    }

    private func refreshIfNeeded() {
      guard case .loading = runtime.loadState else { return }
      Task { @MainActor in await runtime.refresh() }
    }
  }

#endif
