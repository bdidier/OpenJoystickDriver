#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit

  /// An area action shown in the main window's toolbar while its area is selected.
  enum MainWindowToolbarAction: String, CaseIterable {
    case refreshControllers
    case newProfile
    case importProfile
    case installLibraryItem

    var identifier: NSToolbarItem.Identifier {
      NSToolbarItem.Identifier("OpenJoystickDriver.MainWindowToolbar.\(rawValue)")
    }

    init?(identifier: NSToolbarItem.Identifier) {
      guard let action = Self.allCases.first(where: { $0.identifier == identifier }) else {
        return nil
      }
      self = action
    }

    var symbolName: String {
      switch self {
      case .refreshControllers: return "arrow.clockwise"
      case .newProfile: return "plus"
      case .importProfile: return "square.and.arrow.down"
      case .installLibraryItem: return "square.and.arrow.down.on.square"
      }
    }

    /// Localization key of the item's label.
    var labelKey: String {
      switch self {
      case .refreshControllers: return "common.refresh"
      case .newProfile: return "profiles.new"
      case .importProfile: return "profiles.import"
      case .installLibraryItem: return "library.install"
      }
    }

    /// Localization key of the item's tooltip and accessibility description.
    var descriptionKey: String {
      switch self {
      case .refreshControllers: return "controllers.refreshAccessibility"
      case .newProfile: return "profiles.new"
      case .importProfile: return "profiles.import"
      case .installLibraryItem: return "mainMenu.file.installRecordOrMod"
      }
    }
  }

  extension MainWindowArea {
    /// The toolbar actions of the area, in order. Access and Activity keep theirs in content.
    var toolbarActions: [MainWindowToolbarAction] {
      switch self {
      case .controllers: return [.refreshControllers]
      case .profiles: return [.newProfile, .importProfile]
      case .library: return [.installLibraryItem]
      case .access, .activity: return []
      }
    }
  }

  /// Toolbar layout of the main window: the sidebar toggle, then the separator that follows the
  /// sidebar's edge, then flexible space that pushes the selected area's actions to the trailing
  /// edge. The window title and subtitle sit after the separator.
  enum MainWindowToolbarLayout {
    static let toolbar = NSToolbar.Identifier("OpenJoystickDriver.MainWindowToolbar")

    static let fixedItems: [NSToolbarItem.Identifier] = [
      .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace,
    ]

    static func items(for area: MainWindowArea) -> [NSToolbarItem.Identifier] {
      fixedItems + area.toolbarActions.map(\.identifier)
    }

    static var allowedItems: [NSToolbarItem.Identifier] {
      fixedItems + MainWindowToolbarAction.allCases.map(\.identifier)
    }

    static func makeItem(for action: MainWindowToolbarAction) -> NSToolbarItem {
      let item = NSToolbarItem(itemIdentifier: action.identifier)
      let description = OJDLocalized.string(action.descriptionKey)
      item.label = OJDLocalized.string(action.labelKey)
      item.paletteLabel = item.label
      item.toolTip = description
      item.image = NSImage(
        systemSymbolName: action.symbolName,
        accessibilityDescription: description
      )
      item.isBordered = true
      return item
    }
  }

#endif
