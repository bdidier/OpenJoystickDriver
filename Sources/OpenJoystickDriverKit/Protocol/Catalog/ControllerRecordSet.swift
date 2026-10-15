import Foundation

/// Where one part of an effective controller record comes from. The cases are in precedence
/// order, lowest first: a later layer wins over an earlier one.
public enum ControllerRecordLayer: String, Codable, CaseIterable, Sendable {
  /// OJD's built-in default, used when no other layer sets a value.
  case driver
  /// The signed catalog in the app bundle, with its built-in patches.
  case bundled
  /// A file of an installed mod package.
  case package
  /// The user's `all` patch, `all.patch.json`: the first patch of the user layer.
  case global
  /// A file in the user's controller-record directory.
  case user
  /// The active remapping profile.
  case profile
}

/// The kind of a user controller record file.
public enum ControllerRecordOperation: String, Codable, Sendable {
  /// A Controller file: a record for a model the bundled catalog does not have.
  case add
  /// A ControllerPatch file: a merge patch over the records its selector names.
  case patch
}

/// One effective controller record: a bundled record, a Controller file that adds one, or a
/// record with package and user patches applied.
public struct ControllerRecord: Sendable {
  public let model: ControllerModelID
  /// The merged record as a `controller.schema.json` document, with sorted keys.
  public let document: Data
  /// The layer of each top-level field of `document`, except `apiVersion`, `kind`, `vendorID`, and
  /// `productID`.
  public let fieldLayers: [String: ControllerRecordLayer]
  /// The layer of each effective `tuning` key, by its JSON name: `bundled`, `user`, or `global`.
  /// A key no layer sets is absent, and the driver default applies.
  public let tuningLayers: [String: ControllerRecordLayer]
  /// The user file that adds or patches this record, or nil for a bundled record. An `all` patch
  /// is not listed here.
  public let userFile: URL?
  /// The file of an installed package that adds or patches this record, or nil when no package
  /// does. A user file over it wins, and ``layer`` names the user.
  public let packageFile: URL?
  /// The protocol family, such as `xbox.gip`.
  public let family: String
  /// The tuning keys this record's family reads.
  let tuningScope: Set<ControllerTuning.Key>
  let profile: DeviceRuntimeProfile

  /// The effective tuning: the global defaults under the record's own values, per key.
  public var tuning: ControllerTuning { profile.tuning }

  /// Whether the family reaches the controller through raw USB rather than HID.
  public var usesRawUSB: Bool { profile.usesRawUSB }

  /// Who serves the controller: `macos` unless a layer sets `ojd`.
  public var ownership: ControllerOwnership { profile.ownership }

  /// The route the record asks for; nil leaves it to the family.
  public var route: ControllerRecordRoute? { profile.route }

  /// Whether the record is a Switch 2 controller without `bluetoothLE`, which OJD reaches only
  /// over USB, because the Bluetooth LE central needs the vibration characteristic.
  public var isSwitch2WithoutBluetoothLE: Bool {
    profile.physicalProtocolID == .nintendoSwitch2
      && profile.bluetoothLEVibrationCharacteristic == nil
  }

  /// The file of the highest layer that adds or patches this record, or nil for a bundled one.
  public var file: URL? { userFile ?? packageFile }

  /// `user` when a user file adds or patches the record, else `package` when a package does,
  /// `bundled` otherwise.
  public var layer: ControllerRecordLayer {
    userFile != nil ? .user : packageFile != nil ? .package : .bundled
  }
}

/// One file in the user's controller-record directory, or the directory itself when it cannot be
/// read, and whether OJD could apply it.
public struct ControllerRecordFile: Sendable {
  public let url: URL
  /// The model the file names, when it could be read.
  public let model: ControllerModelID?
  public let operation: ControllerRecordOperation?
  /// Why OJD skipped the file, or nil when it applied it.
  public let problem: String?
}

/// A user record file that passed validation, before it is written or applied.
public struct ValidatedControllerRecord: Sendable {
  public let operation: ControllerRecordOperation
  /// The record the file gives: the Controller file's own, or the patched record. Nil for an
  /// `all` patch, which applies to every record.
  public let record: ControllerRecord?
  /// The selector of a patch file, or nil for a Controller file.
  public let selector: ControllerPatch.Selector?

  /// The file name the record file must have in the user directory, such as `045e-028e.json` for a
  /// Controller file and `045e-028e.patch.json` for a patch.
  public var fileName: String {
    selector?.fileName ?? record.map { ControllerRecordSet.fileName(for: $0.model) } ?? ""
  }
}

/// Why a user controller record is invalid, in words for the person who wrote it.
public struct ControllerRecordProblem: Error, Equatable, Sendable, CustomStringConvertible {
  public let description: String

  init(_ description: String) { self.description = description }
}

/// The bundled controller catalog with the user's controller records applied.
///
/// A user file that fails validation is skipped and listed in ``userFiles`` with its reason. The
/// bundled catalog must be valid: a release must not ship a broken record.
public struct ControllerRecordSet: Sendable {
  /// The effective record of every model.
  public let records: [ControllerModelID: ControllerRecord]
  /// Every `.json` file in the user directory except `all.patch.json`, in file-name order, then
  /// the record files of the installed packages in package-name order.
  public let userFiles: [ControllerRecordFile]
  /// The user's `all` patch, applied to every record; none for the bundled catalog alone.
  public let defaults: ControllerDefaults?

  init(
    records: [ControllerModelID: ControllerRecord],
    userFiles: [ControllerRecordFile],
    defaults: ControllerDefaults? = nil
  ) {
    self.records = records
    self.userFiles = userFiles
    self.defaults = defaults
  }

  /// The user files OJD skipped.
  public var problems: [ControllerRecordFile] { userFiles.filter { $0.problem != nil } }

  /// `~/Library/Application Support/OpenJoystickDriver/Controllers`.
  public static var userDirectory: URL {
    MacOSDataDirectory().url(for: .applicationData)
      .appendingPathComponent("Controllers", isDirectory: true)
  }

  /// The bundled catalog alone.
  public static let bundled: ControllerRecordSet = {
    do { return try loadBundled() } catch {
      fatalError("[DeviceCatalog] Invalid controller catalog: \(error)")
    }
  }()

  /// Makes these records the ones every ``ProtocolDriverRegistry`` binds with.
  ///
  /// Returns the models whose effective record changed, added, or went away. Devices that
  /// are already bound keep the record they bound with until they are admitted again.
  @discardableResult
  public func activate() -> Set<ControllerModelID> {
    let catalog = DeviceCatalog(records: self)
    return DeviceCatalog.current.withLock { current in
      defer { current = catalog }
      let models = Set(current.documents.keys).union(catalog.documents.keys)
      return models.filter { current.documents[$0] != catalog.documents[$0] }
    }
  }

  /// `vvvv-pppp.json`, the file name of a record for `model`.
  public static func fileName(for model: ControllerModelID) -> String {
    String(format: "%04x-%04x.json", model.vendorID, model.productID)
  }

  /// The bundled records, decoded once per process.
  private static func loadBundled() throws -> Self {
    let urls = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
      .filter { isRecordFileName($0.lastPathComponent) }.sorted {
        $0.lastPathComponent < $1.lastPathComponent
      }
    guard !urls.isEmpty else { throw ControllerRecordProblem("controller catalog is empty") }
    var records: [ControllerModelID: ControllerRecord] = [:]
    for url in urls {
      do {
        guard
          let document = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            as? [String: Any]
        else { throw ControllerRecordProblem("not a JSON object") }
        let layers = Dictionary(
          uniqueKeysWithValues: fieldNames(of: document).map { ($0, ControllerRecordLayer.bundled) }
        )
        let record = try makeRecord(document, layers: layers)
        guard url.lastPathComponent == fileName(for: record.model) else {
          throw ControllerRecordProblem("filename must be \(fileName(for: record.model))")
        }
        guard records[record.model] == nil else {
          throw ControllerRecordProblem("duplicate controller identity")
        }
        records[record.model] = record
      } catch { throw ControllerRecordProblem("\(url.path): \(problemDescription(error))") }
    }
    return Self(records: records, userFiles: [])
  }

  private static func isRecordFileName(_ name: String) -> Bool {
    guard name.count == 14, name.hasSuffix(".json") else { return false }
    let stem = name.dropLast(5)
    guard stem[stem.index(stem.startIndex, offsetBy: 4)] == "-" else { return false }
    return stem.enumerated().allSatisfy { offset, character in offset == 4 || character.isHexDigit }
  }

  static func decode(
    _ record: [String: Any]
  ) throws -> (model: ControllerModelID, document: ControllerRecordDocument) {
    let data = try JSONSerialization.data(withJSONObject: record)
    let document = try JSONDecoder().decode(ControllerRecordDocument.self, from: data)
    guard let vendorID = UInt16(exactly: document.vendorID),
      let productID = UInt16(exactly: document.productID)
    else { throw ControllerRecordProblem("vendorID must be 1...65535 and productID 0...65535") }
    return (ControllerModelID(vendorID: vendorID, productID: productID), document)
  }

  static func makeRecord(
    _ record: [String: Any],
    layers: [String: ControllerRecordLayer],
    tuningLayers: [String: ControllerRecordLayer]? = nil,
    userFile: URL? = nil,
    packageFile: URL? = nil
  ) throws -> ControllerRecord {
    let decoded = try decode(record)
    let set = decoded.document.tuning.setKeys
    return ControllerRecord(
      model: decoded.model,
      document: try JSONSerialization.data(
        withJSONObject: record,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      ),
      fieldLayers: layers,
      tuningLayers: tuningLayers
        ?? Dictionary(
          uniqueKeysWithValues: set.map { ($0.rawValue, layers["tuning"] ?? .bundled) }
        ),
      userFile: userFile,
      packageFile: packageFile,
      family: decoded.document.protocolInfo.protocolID.rawValue,
      tuningScope: Set(
        ControllerTuning.Key.allCases.filter { decoded.document.tuningScopeViolation($0) == nil }
      ),
      profile: try DeviceCatalog.makeRuntimeProfile(decoded.document)
    )
  }

  static func fieldNames(of record: [String: Any]) -> [String] {
    record.keys.filter { !["apiVersion", "kind", "vendorID", "productID"].contains($0) }
  }

  /// An integer JSON number; booleans and fractions are not integers.
  static func integer(_ value: Any?) -> Int? {
    // swiftlint:disable:next legacy_objc_type
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      let integer = Int(exactly: number.doubleValue)
    else { return nil }
    return integer
  }

  /// A one-line reason for a decoding or file error, with the JSON path of the field.
  public static func problemDescription(_ error: any Error) -> String {
    func path(_ codingPath: [any CodingKey]) -> String {
      codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }
    func located(_ codingPath: [any CodingKey], _ text: String) -> String {
      codingPath.isEmpty ? text : "record.\(path(codingPath)): \(text)"
    }
    switch error {
    case let problem as ControllerRecordProblem: return problem.description
    case DecodingError.dataCorrupted(let context):
      return located(context.codingPath, context.debugDescription)
    case DecodingError.keyNotFound(let key, let context):
      return located(context.codingPath, "missing field \(key.stringValue)")
    case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
      return located(context.codingPath, context.debugDescription)
    default: return error.localizedDescription
    }
  }
}
