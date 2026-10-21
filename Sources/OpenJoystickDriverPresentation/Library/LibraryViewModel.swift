import Combine
import Foundation
import OpenJoystickDriverKit

/// An operation that waits for the person's confirmation in a window-modal sheet.
enum LibraryPending: Identifiable, Equatable {
  case installRecord(data: Data, check: LibraryRecordCheck)
  case installMod(folder: URL, check: LibraryModCheck)
  case removeRecord(LibraryRecordItem)
  case removeMod(LibraryModItem)

  var id: String {
    switch self {
    case .installRecord(_, let check): "installRecord.\(check.fileName)"
    case .installMod(_, let check): "installMod.\(check.name)"
    case .removeRecord(let item): "removeRecord.\(item.identity)"
    case .removeMod(let item): "removeMod.\(item.name)"
    }
  }
}

/// The text and button of a confirmation sheet; its wording matches the action.
struct LibraryConfirmation: Equatable {
  let title: String
  let message: String
  let confirmTitle: String
  let isDestructive: Bool
}

extension LibraryPending {
  var confirmation: LibraryConfirmation {
    switch self {
    case .installRecord(_, let check):
      return LibraryConfirmation(
        title: check.replaces
          ? OJDLocalized.formatted("library.record.replace.title", check.identity)
          : OJDLocalized.formatted("library.record.install.title", check.identity),
        message: check.replaces
          ? OJDLocalized.formatted("library.record.replace.message", check.fileName)
          : OJDLocalized.formatted("library.record.install.message", check.fileName),
        confirmTitle: check.replaces
          ? OJDLocalized.string("library.replace") : OJDLocalized.string("library.install"),
        isDestructive: check.replaces
      )
    case .installMod(_, let check):
      return LibraryConfirmation(
        title: check.replaces
          ? OJDLocalized.formatted("library.mod.replace.title", check.name)
          : OJDLocalized.formatted("library.mod.install.title", check.name),
        message: check.replaces
          ? OJDLocalized.formatted("library.mod.replace.message", check.name, check.version)
          : OJDLocalized.formatted(
            "library.mod.install.message",
            check.name,
            check.version,
            check.author
          ),
        confirmTitle: check.replaces
          ? OJDLocalized.string("library.replace") : OJDLocalized.string("library.install"),
        isDestructive: check.replaces
      )
    case .removeRecord(let item):
      return LibraryConfirmation(
        title: OJDLocalized.formatted("library.record.remove.title", item.identity),
        message: OJDLocalized.string("library.record.remove.message"),
        confirmTitle: OJDLocalized.string("library.remove"),
        isDestructive: true
      )
    case .removeMod(let item):
      return LibraryConfirmation(
        title: OJDLocalized.formatted("library.mod.remove.title", item.name),
        message: OJDLocalized.string("library.mod.remove.message"),
        confirmTitle: OJDLocalized.string("library.remove"),
        isDestructive: true
      )
    }
  }
}

/// Which records the Library list shows: those a file or a mod adds, or those the app comes with.
enum LibraryScope: String, CaseIterable, Identifiable {
  case installed
  case builtIn

  var id: String { rawValue }
  var titleKey: String {
    switch self {
    case .installed: return "library.installed"
    case .builtIn: return "library.builtIn"
    }
  }
}

/// The record or mod the detail column shows.
enum LibrarySelection: Hashable {
  case record(ControllerModelID)
  case mod(String)
}

@MainActor
final class LibraryViewModel: ObservableObject {
  @Published
  var scope: LibraryScope = .installed {
    didSet { if scope != oldValue { select(nil) } }
  }
  /// What the toolbar's search field holds; the list shows only records and mods that match.
  @Published
  var searchText = ""
  @Published
  private(set) var selection: LibrarySelection?
  @Published
  private(set) var records = LibraryRecordListing()
  @Published
  private(set) var mods: [LibraryModItem] = []
  /// The full record of the selected record.
  @Published
  private(set) var recordDetail: LibraryRecordDetail?
  /// The latest test of the selected record.
  @Published
  private(set) var testRun: LibraryTestRun?
  @Published
  private(set) var failure: LibraryFailure?
  /// The result of the latest successful operation, in words.
  @Published
  private(set) var notice: String?
  @Published
  var pending: LibraryPending?

  private let store: any LibraryStore
  private let readFile: (URL) throws -> Data

  init(
    store: any LibraryStore = DirectoryLibraryStore(),
    readFile: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) }
  ) {
    self.store = store
    self.readFile = readFile
  }

  /// The records the list shows under ``scope``.
  var visibleRecords: [LibraryRecordItem] {
    (scope == .installed ? records.installed : records.builtIn).filter {
      $0.matches(searchText)
    }
  }

  /// The mods the list shows under ``scope``; built-in records come with no mods.
  var visibleMods: [LibraryModItem] {
    scope == .installed ? mods.filter { $0.matches(searchText) } : []
  }

  var selectedMod: LibraryModItem? {
    guard case .mod(let name) = selection else { return nil }
    return mods.first { $0.name == name }
  }

  /// Whether Remove applies: a user's record file, or a mod.
  var canRemoveSelection: Bool {
    if selectedMod != nil { return true }
    return recordDetail?.item.isRemovable == true
  }

  var canTestSelection: Bool { recordDetail != nil }

  func reload() {
    records = store.records()
    mods = store.installedMods()
    select(selection)
  }

  /// Shows `selection`; a record or mod that is not in the library selects nothing.
  func select(_ selection: LibrarySelection?) {
    switch selection {
    case .record(let model)?:
      recordDetail = store.recordDetail(model)
      self.selection = recordDetail == nil ? nil : selection
    case .mod(let name)?:
      recordDetail = nil
      self.selection = mods.contains { $0.name == name } ? selection : nil
    case nil:
      recordDetail = nil
      self.selection = nil
    }
    if testRun?.model != recordDetail?.item.model { testRun = nil }
  }

  func dismissFailure() { failure = nil }

  func dismissNotice() { notice = nil }

  /// Checks the record file or mod folder at `url` without installing it; a folder is a mod.
  func validate(at url: URL) {
    perform {
      if try isFolder(url) {
        let check = try store.checkMod(folder: url)
        notice = OJDLocalized.formatted("library.mod.valid", url.lastPathComponent, check.name)
      } else {
        let check = try store.checkRecord(try read(url))
        notice = OJDLocalized.formatted(
          "library.record.valid",
          url.lastPathComponent,
          check.identity
        )
      }
    }
  }

  func beginInstallRecord(from url: URL) {
    perform {
      let data = try read(url)
      pending = .installRecord(data: data, check: try store.checkRecord(data))
    }
  }

  /// Starts installing the record file or mod folder at `url`; a folder is a mod.
  func beginInstall(from url: URL) {
    perform {
      if try isFolder(url) { beginInstallMod(from: url) } else { beginInstallRecord(from: url) }
    }
  }

  private func isFolder(_ url: URL) throws -> Bool {
    do { return try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true } catch {
      throw LibraryFailure(
        message: OJDLocalized.formatted("library.unreadable", url.path, error.localizedDescription),
        code: .fileAccessFailed
      )
    }
  }

  func beginInstallMod(from folder: URL) {
    perform { pending = .installMod(folder: folder, check: try store.checkMod(folder: folder)) }
  }

  /// Asks to remove the selected mod or record file.
  func requestRemoveSelection() {
    if let mod = selectedMod {
      pending = .removeMod(mod)
    } else if let item = recordDetail?.item, item.isRemovable {
      pending = .removeRecord(item)
    }
  }

  /// Replays the capture at `capture` through the selected record's parser and compares the
  /// state with the one at `expectation`.
  func testSelectedRecord(capture: URL, expectation: URL) {
    guard let model = recordDetail?.item.model else { return }
    perform {
      testRun = nil
      let result = try store.testRecord(
        model,
        capture: try read(capture),
        captureName: capture.lastPathComponent,
        expectation: try read(expectation),
        expectationName: expectation.lastPathComponent
      )
      testRun = LibraryTestRun(
        model: model,
        expectation: expectation.lastPathComponent,
        result: result
      )
    }
  }

  func cancelPending() { pending = nil }

  /// Runs the confirmed operation. Returns whether it changed the library.
  @discardableResult
  func confirmPending() -> Bool {
    guard let operation = pending else { return false }
    pending = nil
    return perform {
      switch operation {
      case .installRecord(let data, _):
        let check = try store.installRecord(data)
        notice = OJDLocalized.formatted("library.record.installed", check.identity)
      case .installMod(let folder, let check):
        try store.installMod(folder: folder, replace: check.replaces)
        notice = OJDLocalized.formatted("library.mod.installed", check.name)
      case .removeRecord(let item):
        try store.removeRecord(item.model)
        notice = OJDLocalized.formatted("library.record.removed", item.identity)
      case .removeMod(let item):
        try store.removeMod(name: item.name)
        notice = OJDLocalized.formatted("library.mod.removed", item.name)
      }
      reload()
    }
  }

  private func read(_ url: URL) throws -> Data {
    do { return try readFile(url) } catch {
      throw LibraryFailure(
        message: OJDLocalized.formatted(
          "library.unreadable",
          url.path,
          error.localizedDescription
        ),
        code: .fileAccessFailed
      )
    }
  }

  @discardableResult
  private func perform(_ body: () throws -> Void) -> Bool {
    failure = nil
    notice = nil
    do {
      try body()
      return true
    } catch let error as LibraryFailure {
      failure = error
    } catch {
      failure = LibraryFailure(message: error.localizedDescription, code: nil)
    }
    return false
  }
}
