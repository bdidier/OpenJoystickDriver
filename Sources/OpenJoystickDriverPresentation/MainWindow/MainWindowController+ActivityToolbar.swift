#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit

  extension MainWindowController {
    /// The Activity toolbar items that are not plain buttons: the view switch, the stream
    /// filter, the line count and the search field. Nil for every other action.
    func makeActivityControlItem(for action: MainWindowToolbarAction) -> NSToolbarItem? {
      switch action {
      case .activityMode:
        return makeSegmentedItem(
          for: action,
          titleKeys: ActivityMode.allCases.map(\.titleKey),
          selectedIndex: screens.activity.mode.rawValue,
          selector: #selector(selectActivityMode(_:))
        )
      case .activityFilter: return makeFilterItem(for: action)
      case .activitySearch: return makeSearchItem(for: action)
      case .newProfile, .importProfile, .validateProfileFile,
        .duplicateProfile, .exportProfile, .deleteProfile, .installLibraryItem, .grantProgram,
        .createToken, .validateLibraryItem, .testLibraryRecord, .removeLibraryItem,
        .searchLibrary, .copyActivityLog, .saveActivityLog, .showActivityLogInFinder,
        .runDiagnostics:
        return nil
      }
    }

    private func makeSegmentedItem(
      for action: MainWindowToolbarAction,
      titleKeys: [String],
      selectedIndex: Int,
      selector: Selector
    ) -> NSToolbarItem {
      let group = NSToolbarItemGroup(
        itemIdentifier: action.identifier,
        titles: titleKeys.map { OJDLocalized.string($0) },
        selectionMode: .selectOne,
        labels: nil,
        target: self,
        action: selector
      )
      group.controlRepresentation = .expanded
      group.selectedIndex = selectedIndex
      group.label = OJDLocalized.string(action.labelKey)
      group.paletteLabel = group.label
      group.toolTip = OJDLocalized.string(action.descriptionKey)
      return group
    }

    /// One menu holds the stream filter and the line count, so the toolbar fits at the window's
    /// minimum width without an overflow chevron.
    private func makeFilterItem(for action: MainWindowToolbarAction) -> NSToolbarItem {
      let item = NSMenuToolbarItem(itemIdentifier: action.identifier)
      item.label = OJDLocalized.string(action.labelKey)
      item.paletteLabel = item.label
      item.toolTip = OJDLocalized.string(action.descriptionKey)
      item.image = NSImage(
        systemSymbolName: action.symbolName,
        accessibilityDescription: item.toolTip
      )
      item.showsIndicator = true
      let menu = NSMenu()
      for filter in ActivityLogFilter.allCases {
        let entry = NSMenuItem(
          title: OJDLocalized.string(filter.titleKey),
          action: #selector(selectActivityFilter(_:)),
          keyEquivalent: ""
        )
        entry.target = self
        entry.tag = filter.rawValue
        menu.addItem(entry)
      }
      menu.addItem(.separator())
      let heading = NSMenuItem(
        title: OJDLocalized.string("ui.activity.lines"),
        action: nil,
        keyEquivalent: ""
      )
      heading.isEnabled = false
      menu.addItem(heading)
      for count in ActivityLogLineCount.choices {
        let entry = NSMenuItem(
          title: count.formatted(),
          action: #selector(selectActivityLineCount(_:)),
          keyEquivalent: ""
        )
        entry.target = self
        entry.tag = count
        menu.addItem(entry)
      }
      item.menu = menu
      return item
    }

    private func makeSearchItem(for action: MainWindowToolbarAction) -> NSToolbarItem {
      let item = NSSearchToolbarItem(itemIdentifier: action.identifier)
      item.label = OJDLocalized.string(action.labelKey)
      item.paletteLabel = item.label
      item.toolTip = OJDLocalized.string(action.descriptionKey)
      item.fixSearchFieldWidth()
      item.searchField.placeholderString = item.label
      item.searchField.stringValue = screens.activity.log.searchText
      item.searchField.sendsSearchStringImmediately = true
      item.searchField.target = self
      item.searchField.action = #selector(searchActivityLog(_:))
      return item
    }

    @objc
    func selectActivityMode(_ sender: NSToolbarItemGroup) {
      guard let mode = ActivityMode(rawValue: sender.selectedIndex) else { return }
      screens.activity.mode = mode
    }

    @objc
    func selectActivityFilter(_ sender: NSMenuItem) {
      guard let filter = ActivityLogFilter(rawValue: sender.tag) else { return }
      screens.activity.log.filter = filter
    }

    @objc
    func selectActivityLineCount(_ sender: NSMenuItem) {
      screens.activity.log.setLineCount(sender.tag)
      screens.supportReport.logExportLines = sender.tag
    }

    @objc
    func searchActivityLog(_ sender: NSSearchField) {
      screens.activity.log.searchText = sender.stringValue
    }

    /// Asks where to save the end of the logs, then writes them as `ojd log export` does, through
    /// the same model as the Save Activity Log menu item.
    func saveActivityLog() {
      guard let window else { return }
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("ui.debug.saveLogsPanel")
      panel.message = ApplicationServiceLogService.sharingWarning
      panel.nameFieldStringValue = screens.supportReport.defaultSupportLogsFilename
      panel.canCreateDirectories = true
      panel.beginSheetModal(for: window) { [weak self] response in
        guard response == .OK, let url = panel.url else { return }
        Task { @MainActor in
          guard let self else { return }
          await self.screens.supportReport.saveSupportLogs(to: url)
          if case .error(let message) = self.screens.supportReport.supportLogsState {
            self.screens.activity.failure = ActivityActionFailure(
              title: OJDLocalized.string("ui.menu.file.saveFailed"),
              message: message
            )
          }
        }
      }
    }

    func showActivityLogInFinder() {
      if !screens.activity.log.showInFinder() {
        screens.activity.failure = ActivityActionFailure(
          title: OJDLocalized.string("ui.activity.showInFinder.failed"),
          message: nil
        )
      }
    }

    /// Follows the logs while the window is visible and shows the log, and stops otherwise.
    func updateLogFollowing() {
      guard let window else { return }
      screens.activity.log.setFollowing(
        ActivityLogFollowing.shouldFollow(
          windowVisible: window.isVisible && !window.isMiniaturized,
          area: navigation.selectedArea,
          mode: screens.activity.mode
        )
      )
    }
  }

  extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
      if menuItem.action == #selector(selectActivityLineCount(_:)) {
        menuItem.state = menuItem.tag == screens.activity.log.lineCount ? .on : .off
      } else if menuItem.action == #selector(selectActivityFilter(_:)) {
        menuItem.state = menuItem.tag == screens.activity.log.filter.rawValue ? .on : .off
      }
      return true
    }
  }

#endif
