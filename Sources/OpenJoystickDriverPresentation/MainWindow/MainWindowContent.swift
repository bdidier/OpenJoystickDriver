#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension MainWindowArea {
    var title: String { OJDLocalized.string(titleKey) }
  }

  /// The main window's sidebar: one row per area, in `Command-1` to `Command-5` order. A row
  /// that the navigation model refuses leaves the selection on the area still shown.
  struct MainWindowSidebar: View {
    @ObservedObject
    var navigation: MainWindowNavigationModel

    var body: some View {
      List(selection: selection) {
        ForEach(MainWindowArea.allCases) { area in
          Label(area.title, systemImage: area.symbolName).tag(area)
        }
      }.listStyle(SidebarListStyle()).frame(
        minWidth: MainWindowSizingPolicy.sidebarWidth.minimum,
        maxWidth: MainWindowSizingPolicy.sidebarWidth.maximum
      )
      .ojdAccessibilityLabel(OJDLocalized.string("a11y.mainWindow.sidebar"))
    }

    private var selection: Binding<MainWindowArea?> {
      Binding(
        get: { navigation.selectedArea },
        set: { area in if let area { navigation.requestArea(area) } }
      )
    }
  }

  /// The models each area's screen reads. One instance lives as long as the main window.
  @MainActor
  struct MainWindowScreens {
    let runtime: RuntimeViewModel
    let supportReport: SupportReportModel
    let controllers: ControllersViewModel
    let library: ProfileLibraryModel
    let profiles: ProfilesViewModel
    let activity: ActivityModel
    let errorCodeExplainer: ErrorCodeExplainerModel
    let libraryArea: LibraryViewModel
    let access: AccessViewModel
    let restartApplication: @MainActor () -> Void
    let openInputTest: @MainActor (ApplicationServiceDeviceDescription) -> Void
  }

  /// The main window's content list column: the selected area's list half, or nothing for an
  /// area without one.
  struct MainWindowListRoot: View {
    @ObservedObject
    var navigation: MainWindowNavigationModel
    @ObservedObject
    var runtime: RuntimeViewModel
    @ObservedObject
    var profiles: ProfilesViewModel
    let screens: MainWindowScreens

    var body: some View {
      list.id(navigation.selectedArea).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var list: some View {
      switch navigation.selectedArea {
      case .controllers:
        ControllersView(
          screen: screens.controllers,
          column: .list,
          openInputTest: screens.openInputTest
        )
      case .profiles:
        ProfilesView(
          viewModel: runtime,
          library: screens.library,
          navigation: navigation,
          screen: profiles,
          column: .list
        )
      case .library: LibraryAreaView(runtime: runtime, model: screens.libraryArea, column: .list)
      case .access, .activity: EmptyView()
      }
    }
  }

  /// The main window's content: the problem banner while something is wrong, then the
  /// selected area.
  struct MainWindowRoot: View {
    @ObservedObject
    var navigation: MainWindowNavigationModel
    @ObservedObject
    var runtime: RuntimeViewModel
    @ObservedObject
    var profiles: ProfilesViewModel
    let screens: MainWindowScreens
    @State
    private var driverApprovalFailed = false

    var body: some View {
      VStack(spacing: 0) {
        MainWindowProblemBanner(
          problems: MainWindowProblem.current(
            status: runtime.statusState,
            driver: runtime.systemExtensionSetupState
          ),
          perform: perform
        )
        area.id(navigation.selectedArea).frame(maxWidth: .infinity, maxHeight: .infinity)
      }.frame(
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
      ).background(
        Color.clear.alert(isPresented: $driverApprovalFailed) {
          Alert(
            title: Text(OJDLocalized.string("setup.openSystemSettingsFailed")),
            dismissButton: .default(Text(OJDLocalized.string("common.ok")))
          )
        }
      ).background(ErrorCodeExplainerSheetHost(model: screens.errorCodeExplainer)).alert(
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
      case .controllers:
        ControllersView(
          screen: screens.controllers,
          column: .detail,
          openInputTest: screens.openInputTest
        )
      case .profiles:
        ProfilesView(
          viewModel: runtime,
          library: screens.library,
          navigation: navigation,
          screen: profiles,
          column: .detail
        )
      case .library: LibraryAreaView(runtime: runtime, model: screens.libraryArea, column: .detail)
      case .access:
        AccessAreaView(
          runtime: runtime,
          model: screens.access,
          restartApplication: screens.restartApplication
        )
      case .activity: ActivityView(model: screens.activity)
      }
    }

    private func perform(_ action: MainWindowProblemAction) {
      switch action {
      case .retryService: Task { @MainActor in await runtime.refresh() }
      case .openDriverApproval: driverApprovalFailed = !SystemExtensionApproval.openSystemSettings()
      case .repairDriver: Task { @MainActor in await runtime.repairSystemExtension() }
      case .showAccess: navigation.requestArea(.access)
      }
    }

    private func refreshIfNeeded() {
      guard case .loading = runtime.loadState else { return }
      Task { @MainActor in await runtime.refresh() }
    }
  }

#endif
