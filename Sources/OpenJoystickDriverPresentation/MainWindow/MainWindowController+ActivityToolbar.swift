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
      case .activityFilter:
        return makeSegmentedItem(
          for: action,
          titleKeys: ActivityLogFilter.allCases.map(\.titleKey),
          selectedIndex: screens.activity.log.filter.rawValue,
          selector: #selector(selectActivityFilter(_:))
        )
      case .activityLines: return makeLinesItem(for: action)
      case .activitySearch: return makeSearchItem(for: action)
      case .refreshControllers, .newProfile, .importProfile, .installLibraryItem,
        .copyActivityLog, .saveActivityLog, .showActivityLogInFinder, .runDiagnostics:
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

    private func makeLinesItem(for action: MainWindowToolbarAction) -> NSToolbarItem {
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
    func selectActivityFilter(_ sender: NSToolbarItemGroup) {
      guard let filter = ActivityLogFilter(rawValue: sender.selectedIndex) else { return }
      screens.activity.log.filter = filter
    }

    @objc
    func selectActivityLineCount(_ sender: NSMenuItem) {
      screens.activity.log.setLineCount(sender.tag)
    }

    @objc
    func searchActivityLog(_ sender: NSSearchField) {
      screens.activity.log.searchText = sender.stringValue
    }

    /// Asks where to save the end of the logs, then writes them as `ojd log export` does.
    func saveActivityLog() {
      guard let window else { return }
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("debug.saveLogsPanel")
      panel.message = ApplicationServiceLogService.sharingWarning
      panel.nameFieldStringValue = screens.supportReport.defaultSupportLogsFilename
      panel.canCreateDirectories = true
      panel.beginSheetModal(for: window) { [weak self] response in
        guard response == .OK, let url = panel.url else { return }
        Task { @MainActor in await self?.screens.activity.log.save(to: url) }
      }
    }
  }

  extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
      if menuItem.action == #selector(selectActivityLineCount(_:)) {
        menuItem.state = menuItem.tag == screens.activity.log.lineCount ? .on : .off
      }
      return true
    }
  }

#endif
