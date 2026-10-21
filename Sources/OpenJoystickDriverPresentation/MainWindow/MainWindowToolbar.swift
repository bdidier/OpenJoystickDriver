#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit

  /// An area action shown in the main window's toolbar while its area is selected.
  enum MainWindowToolbarAction: String, CaseIterable {
    case refreshControllers
    case newProfile
    case importProfile
    case validateProfileFile
    case duplicateProfile
    case exportProfile
    case deleteProfile
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
      case .validateProfileFile: return "checkmark.seal"
      case .duplicateProfile: return "plus.square.on.square"
      case .exportProfile: return "square.and.arrow.up"
      case .deleteProfile: return "trash"
      case .installLibraryItem: return "square.and.arrow.down.on.square"
      }
    }

    /// Localization key of the item's label.
    var labelKey: String {
      switch self {
      case .refreshControllers: return "common.refresh"
      case .newProfile: return "profiles.new"
      case .importProfile: return "profiles.import"
      case .validateProfileFile: return "profiles.validateFile"
      case .duplicateProfile: return "common.duplicate"
      case .exportProfile: return "profiles.export"
      case .deleteProfile: return "common.delete"
      case .installLibraryItem: return "library.install"
      }
    }

    /// Localization key of the item's tooltip and accessibility description.
    var descriptionKey: String {
      switch self {
      case .refreshControllers: return "controllers.refreshAccessibility"
      case .newProfile: return "profiles.new"
      case .importProfile: return "profiles.import"
      case .validateProfileFile: return "profiles.validateFile"
      case .duplicateProfile: return "common.duplicate"
      case .exportProfile: return "profiles.export"
      case .deleteProfile: return "common.delete"
      case .installLibraryItem: return "mainMenu.file.installRecordOrMod"
      }
    }
  }

  /// What decides whether the Profiles toolbar actions are enabled.
  struct ProfileToolbarState: Equatable {
    /// A profile of the library is selected.
    let hasSelection: Bool
    /// A mutation or recovery is running, or the library has damaged entries.
    let isBlocked: Bool
    /// The editor holds changes that are not saved.
    let hasUnsavedChanges: Bool
  }

  extension MainWindowToolbarAction {
    /// Duplicate and Export act on the saved profile, so they wait for the editor's changes to
    /// be saved.
    var needsSavedProfile: Bool { self == .duplicateProfile || self == .exportProfile }

    /// Whether a Profiles action is enabled; other actions are always enabled here.
    func isEnabled(profile state: ProfileToolbarState) -> Bool {
      switch self {
      case .newProfile, .importProfile: return !state.isBlocked
      case .validateProfileFile: return true
      case .exportProfile: return state.hasSelection && !state.hasUnsavedChanges
      case .duplicateProfile:
        return state.hasSelection && !state.isBlocked && !state.hasUnsavedChanges
      case .deleteProfile: return state.hasSelection && !state.isBlocked
      case .refreshControllers, .installLibraryItem: return true
      }
    }
  }

  extension MainWindowArea {
    /// The toolbar actions of the area, in order. Access and Activity keep theirs in content.
    var toolbarActions: [MainWindowToolbarAction] {
      switch self {
      case .controllers: return [.refreshControllers]
      case .profiles:
        return [
          .newProfile, .importProfile, .validateProfileFile, .duplicateProfile, .exportProfile,
          .deleteProfile,
        ]
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
