import Foundation

/// A `ControllerPatch` document from `controller-patch.schema.json`: an RFC 7396 merge patch and
/// the selector of the records it applies to.
///
/// The layers apply in the order catalog record, built-in patch, package patch, user patch. Inside
/// one layer the selectors apply in the order `all`, `vendorID` with `productID`, `model`, so the
/// more specific selector wins. A `null` deletes a key and an array replaces the array.
/// `Scripts/Catalog/controller_patch.py` implements the same rules, and both read the cases in
/// `Tests/RepositoryScripts/fixtures/controller_patch/cases.json`.
public struct ControllerPatch: Equatable, Sendable {
  /// Which records a patch applies to.
  public enum Selector: Equatable, Sendable, CustomStringConvertible {
    /// Every record. Such a patch may set only `tuning`.
    case all
    /// The record with this vendor ID and product ID.
    case identity(ControllerModelID)
    /// The record with this model id, `vvvv-pppp` in lowercase hex until records carry their own.
    case model(String)

    /// 0 for `all`, 1 for `vendorID` with `productID`, 2 for `model`: a higher rank applies later.
    public var rank: Int {
      switch self {
      case .all: 0
      case .identity: 1
      case .model: 2
      }
    }

    public var description: String {
      switch self {
      case .all: "all controllers"
      case .identity(let model): model.description
      case .model(let id): id
      }
    }

    /// The file name of a patch with this selector in a `Controllers` folder.
    public var fileName: String {
      switch self {
      case .all: "all.patch.json"
      case .identity(let model):
        String(format: "%04x-%04x.patch.json", model.vendorID, model.productID)
      case .model(let id): "model-\(id).patch.json"
      }
    }

    /// Whether a patch with this selector applies to `model`.
    public func selects(_ model: ControllerModelID) -> Bool {
      switch self {
      case .all: true
      case .identity(let identity): identity == model
      case .model(let id): id == ControllerPatch.modelID(of: model)
      }
    }
  }

  /// The `kind` of a patch document.
  public static let kind = "ControllerPatch"
  /// The top-level record sections a patch may set.
  static let sections: Set<String> = [
    "modes", "usb", "bluetoothLE", "server", "route", "output", "input",
    "tuning",
  ]

  public let selector: Selector
  /// The merge patch as sorted-key JSON.
  let bodyData: Data

  /// The merge patch.
  var body: [String: Any] {
    (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
  }

  init(selector: Selector, body: [String: Any]) throws {
    self.selector = selector
    bodyData = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
  }

  /// The model id of `model`: `vvvv-pppp` in lowercase hex.
  public static func modelID(of model: ControllerModelID) -> String {
    String(format: "%04x-%04x", model.vendorID, model.productID)
  }

  /// The document of a patch with `selector` and `body`.
  static func document(selector: Selector, body: [String: Any]) -> [String: Any] {
    let selected: [String: Any]
    switch selector {
    case .all: selected = ["all": true]
    case .identity(let model):
      selected = ["vendorID": Int(model.vendorID), "productID": Int(model.productID)]
    case .model(let id): selected = ["model": id]
    }
    return [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": kind, "selector": selected,
      "patch": body,
    ]
  }

  /// Checks and reads a patch document. A document of another kind, such as the removed
  /// `ControllerOverride`, fails the header check.
  static func parse(_ document: [String: Any], file: String? = nil) throws -> Self {
    try OpenJoystickDriverAPI.requireHeader(document, kind: kind, file: file)
    guard Set(document.keys) == ["apiVersion", "kind", "selector", "patch"],
      let selector = document["selector"] as? [String: Any],
      let body = document["patch"] as? [String: Any]
    else {
      throw ControllerRecordProblem(
        "the file must hold exactly apiVersion, kind, selector, and patch"
      )
    }
    let parsed = try parseSelector(selector)
    guard !body.isEmpty, Set(body.keys).isSubset(of: sections) else {
      throw ControllerRecordProblem(
        "patch must hold modes, usb, bluetoothLE, server, "
          + "route, output, input, or tuning"
      )
    }
    if parsed == .all, Set(body.keys) != ["tuning"] {
      throw ControllerRecordProblem("an all patch may set only tuning")
    }
    return try Self(selector: parsed, body: body)
  }

  /// A JSON integer: a boolean, a fraction, a number written as a float, and a string are not.
  static func strictInteger(_ value: Any?) -> Int? {
    // swiftlint:disable:next legacy_objc_type
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      !CFNumberIsFloatType(number)
    else { return nil }
    return number.intValue
  }

  private static func parseSelector(_ selector: [String: Any]) throws -> Selector {
    switch Set(selector.keys) {
    case ["all"]:
      // swiftlint:disable:next legacy_objc_type
      guard let flag = selector["all"] as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID(),
        flag.boolValue
      else { throw ControllerRecordProblem("selector.all must be true") }
      return .all
    case ["vendorID", "productID"]:
      guard
        let vendorID = strictInteger(selector["vendorID"]).flatMap(
          UInt16.init(exactly:)
        ),
        vendorID >= 1,
        let productID = strictInteger(selector["productID"]).flatMap(
          UInt16.init(exactly:)
        )
      else { throw ControllerRecordProblem("vendorID must be 1...65535 and productID 0...65535") }
      return .identity(ControllerModelID(vendorID: vendorID, productID: productID))
    case ["model"]:
      guard let id = selector["model"] as? String, isModelID(id) else {
        throw ControllerRecordProblem("selector.model must be vvvv-pppp in lowercase hex")
      }
      return .model(id)
    default:
      throw ControllerRecordProblem(
        "selector must be all, model, or vendorID with productID"
      )
    }
  }

  private static func isModelID(_ text: String) -> Bool {
    let characters = Array(text)
    return characters.count == 9 && characters[4] == "-"
      && characters.enumerated().allSatisfy { offset, character in
        offset == 4 || ("0"..."9" ~= character || "a"..."f" ~= character)
      }
  }
}

/// The RFC 7396 merge that layers controller patches over a record.
enum ControllerPatchMerge {
  /// RFC 7396 `MergePatch`: `null` deletes, an array or scalar replaces. An object patch over a
  /// value that is not an object starts from an empty object.
  static func mergePatch(_ target: Any?, _ patch: Any) -> Any {
    guard let patch = patch as? [String: Any] else { return patch }
    var result = target as? [String: Any] ?? [:]
    for (key, value) in patch {
      if value is NSNull {
        result.removeValue(forKey: key)
      } else {
        result[key] = mergePatch(result[key], value)
      }
    }
    return result
  }

  /// `items` ordered for one layer, least specific first: by selector rank, then file name, then
  /// owning package name (a user file has none), then position, so the order is total and the
  /// same on every run.
  static func ordered<Item>(
    _ items: [Item],
    by key: (Item) -> (patch: ControllerPatch, owner: String?)
  ) -> [Item] {
    items.enumerated().map { (offset: $0.offset, item: $0.element, key: key($0.element)) }
      .sorted {
        (
          $0.key.patch.selector.rank, $0.key.patch.selector.fileName, $0.key.owner ?? "",
          $0.offset
        )
          < (
            $1.key.patch.selector.rank, $1.key.patch.selector.fileName, $1.key.owner ?? "",
            $1.offset
          )
      }
      .map(\.item)
  }

  /// `patches` ordered for one layer, with no owners.
  static func ordered(_ patches: [ControllerPatch]) -> [ControllerPatch] {
    ordered(patches) { ($0, nil) }
  }

  /// The merge patch that `patch` gives to the record `document`, or nil when it changes nothing
  /// to apply. A patch with a selector other than `all` gives its whole body. An `all` patch gives
  /// only the `tuning` keys that the record's family reads; a `tuning` that is not an object gives
  /// nothing.
  static func appliedBody(of patch: ControllerPatch, to document: [String: Any]) -> [String: Any]? {
    let body = patch.body
    guard patch.selector == .all else { return body }
    let scope = Set(ControllerTuning.scope(ofDocument: document).map(\.rawValue))
    let tuning = (body["tuning"] as? [String: Any] ?? [:]).filter { scope.contains($0.key) }
    return tuning.isEmpty ? nil : ["tuning": tuning]
  }

  /// `document` with `patch` merged in; `document` itself when the patch gives nothing.
  static func apply(_ patch: ControllerPatch, to document: [String: Any]) -> [String: Any] {
    guard let body = appliedBody(of: patch, to: document) else { return document }
    return mergePatch(document, body) as? [String: Any] ?? document
  }

  /// `record` with the built-in, package, and user patches applied in that order. A package layer
  /// entry may name its owner. A record with no valid `vendorID` and `productID` is returned
  /// unchanged.
  static func effective(
    record: [String: Any],
    builtin: [ControllerPatch],
    package: [(patch: ControllerPatch, owner: String?)],
    user: [ControllerPatch]
  ) -> [String: Any] {
    guard
      let vendorID = ControllerPatch.strictInteger(record["vendorID"]).flatMap(
        UInt16.init(exactly:)
      ),
      let productID = ControllerPatch.strictInteger(record["productID"]).flatMap(
        UInt16.init(exactly:)
      )
    else { return record }
    let model = ControllerModelID(vendorID: vendorID, productID: productID)
    let layers: [[(patch: ControllerPatch, owner: String?)]] = [
      builtin.map { ($0, nil) }, package, user.map { ($0, nil) },
    ]
    var result = record
    for layer in layers {
      for entry in ordered(layer.filter { $0.patch.selector.selects(model) }, by: { $0 }) {
        result = apply(entry.patch, to: result)
      }
    }
    return result
  }
}
