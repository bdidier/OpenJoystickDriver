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

/// The Library list's rows; the detail column shows the selected one.
enum LibrarySection: String, CaseIterable, Identifiable {
  case records
  case mods

  var id: String { rawValue }
  var titleKey: String { "library.\(rawValue)" }
  var symbolName: String { self == .records ? "doc.text" : "shippingbox" }
}

@MainActor
final class LibraryViewModel: ObservableObject {
  @Published
  var selectedSection: LibrarySection = .records
  @Published
  private(set) var records = LibraryRecordListing()
  @Published
  private(set) var mods: [LibraryModItem] = []
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

  func reload() {
    records = store.installedRecords()
    mods = store.installedMods()
  }

  func dismissFailure() { failure = nil }

  func dismissNotice() { notice = nil }

  func validateRecord(at url: URL) {
    perform {
      let check = try store.checkRecord(try read(url))
      notice = OJDLocalized.formatted(
        "library.record.valid",
        url.lastPathComponent,
        check.identity
      )
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
    let isFolder: Bool
    do {
      isFolder = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    } catch {
      failure = LibraryFailure(
        message: OJDLocalized.formatted("library.unreadable", url.path, error.localizedDescription),
        code: .fileAccessFailed
      )
      return
    }
    if isFolder { beginInstallMod(from: url) } else { beginInstallRecord(from: url) }
  }

  func validateMod(at folder: URL) {
    perform {
      let check = try store.checkMod(folder: folder)
      notice = OJDLocalized.formatted("library.mod.valid", folder.lastPathComponent, check.name)
    }
  }

  func beginInstallMod(from folder: URL) {
    perform { pending = .installMod(folder: folder, check: try store.checkMod(folder: folder)) }
  }

  func requestRemove(_ item: LibraryRecordItem) { pending = .removeRecord(item) }

  func requestRemove(_ item: LibraryModItem) { pending = .removeMod(item) }

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
