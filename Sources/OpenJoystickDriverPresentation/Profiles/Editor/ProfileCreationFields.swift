import Foundation
import OpenJoystickDriverKit

/// A controller a new profile can target: a connected controller, or a controller model that is
/// not connected. `ojd profile create --controller` accepts both.
struct ProfileControllerChoice: Equatable, Identifiable {
  /// Where the picker lists the choice.
  enum Group: Equatable {
    case connected
    case profiles
    /// A catalog model, under the label of its protocol family.
    case family(String)
  }

  let id: String
  /// The controller's own name; nil for a model that is not connected.
  let name: String?
  let vendorID: UInt16
  let productID: UInt16
  /// The label of the model's protocol family, when the catalog has the model.
  let familyLabel: String?
  let group: Group

  /// The name in the picker: the controller's name, else the family and the vendor and product
  /// identifiers of the model. The catalog has no product names.
  var label: String {
    if let name = OJDValue.reported(name).textOrNil { return name }
    let identifiers = OJDValue.usbIdentifier(vendorID: vendorID, productID: productID).displayText
    return familyLabel.map { "\($0) · \(identifiers)" } ?? identifiers
  }

  /// The connected controllers, then the models that none of them has: first those of `profiles`,
  /// then those of `catalog`, which maps each catalog model to its family label. Models are
  /// ordered by vendor and product; catalog models by family label first.
  static func choices(
    devices: [ApplicationServiceDeviceDescription],
    profiles: [RemappingProfile],
    catalog: [ControllerModelID: String]
  ) -> [Self] {
    let connected = devices.map {
      Self(
        id: $0.sessionToken.rawValue,
        name: $0.name,
        vendorID: $0.vendorID,
        productID: $0.productID,
        familyLabel: catalog[ControllerModelID(vendorID: $0.vendorID, productID: $0.productID)],
        group: .connected
      )
    }
    var seen = Set(
      connected.map { ControllerModelID(vendorID: $0.vendorID, productID: $0.productID) }
    )
    func models(_ ids: [ControllerModelID], group: (String?) -> Group) -> [Self] {
      ids.sorted().compactMap { model in
        guard seen.insert(model).inserted else { return nil }
        return Self(
          id: String(format: "model-%04X-%04X", model.vendorID, model.productID),
          name: nil,
          vendorID: model.vendorID,
          productID: model.productID,
          familyLabel: catalog[model],
          group: group(catalog[model])
        )
      }
    }
    let known = models(
      profiles.map {
        ControllerModelID(vendorID: $0.device.vendorID, productID: $0.device.productID)
      }
    ) { _ in .profiles }
    let families = models(Array(catalog.keys)) { .family($0 ?? "") }
    let ordered = families.sorted { left, right in
      if left.group != right.group { return left.familyLabel ?? "" < right.familyLabel ?? "" }
      return (left.vendorID, left.productID) < (right.vendorID, right.productID)
    }
    return connected + known + ordered
  }
}

/// A titled run of choices in the picker.
struct ProfileControllerGroup: Equatable, Identifiable {
  let title: String
  let choices: [ProfileControllerChoice]
  var id: String { title }

  /// The sections of `choices`, in their order: connected controllers, controllers of existing
  /// profiles, then one section per protocol family.
  static func sections(of choices: [ProfileControllerChoice]) -> [Self] {
    var sections: [Self] = []
    for choice in choices {
      let title: String
      switch choice.group {
      case .connected: title = OJDLocalized.string("settings.controllerConnectedShort")
      case .profiles: title = OJDLocalized.string("profiles.controllersOfProfiles")
      case .family(let label): title = label
      }
      if let last = sections.last, last.title == title {
        sections[sections.count - 1] = Self(title: title, choices: last.choices + [choice])
      } else {
        sections.append(Self(title: title, choices: [choice]))
      }
    }
    return sections
  }
}

/// What the New Profile sheet knows besides the fields: the controllers it offers and the
/// profiles that already exist.
struct ProfileCreationContext: Equatable {
  let choices: [ProfileControllerChoice]
  let profiles: [RemappingProfile]

  var sections: [ProfileControllerGroup] { ProfileControllerGroup.sections(of: choices) }
}

/// The names profiles can have among `profiles`.
enum ProfileNaming {
  /// Whether another profile has `name`, compared as the profile library compares names.
  static func isTaken(_ name: String, in profiles: [RemappingProfile]) -> Bool {
    let key = RemappingProfile.normalizedName(ProfileNameValidation.trimmedName(name))
    return profiles.contains { RemappingProfile.normalizedName($0.name) == key }
  }

  /// `base`, or `base 2`, `base 3` and so on for the first name no profile has. An empty base
  /// stays empty.
  static func availableName(_ base: String, in profiles: [RemappingProfile]) -> String {
    guard !base.isEmpty, isTaken(base, in: profiles) else { return base }
    var number = 2
    while isTaken("\(base) \(number)", in: profiles) { number += 1 }
    return "\(base) \(number)"
  }
}

/// The edits made in the New Profile sheet. Nothing is stored that the controller list decides:
/// the chosen controller is the one the person picked while it is offered, else the first, and the
/// name is the one the person typed, else the chosen controller's name.
struct ProfileCreationFields: Equatable {
  var editedName: String?
  var selectedControllerID: String?
  var scopeKind = ProfileScopeKind.global
  var appID = ""
  /// The output policy `ojd profile create` starts with.
  var outputPolicy = RemappingOutputPolicy(virtualGamepad: .passthrough, physicalInput: .shared)

  /// The controller the profile will belong to.
  func controller(in context: ProfileCreationContext) -> ProfileControllerChoice? {
    context.choices.first { $0.id == selectedControllerID } ?? context.choices.first
  }

  /// The name field: the typed name, else the chosen controller's name made free of existing
  /// names; empty when the controller has no name.
  func name(in context: ProfileCreationContext) -> String {
    editedName
      ?? ProfileNaming.availableName(
        Self.controllerName(controller(in: context)),
        in: context.profiles
      )
  }

  static func controllerName(_ choice: ProfileControllerChoice?) -> String {
    choice?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  func isNameTaken(in context: ProfileCreationContext) -> Bool {
    ProfileNaming.isTaken(name(in: context), in: context.profiles)
  }

  /// The profile these fields describe, or nil while a field is missing or invalid or the name is
  /// taken.
  func proposedProfile(in context: ProfileCreationContext) -> RemappingProfile? {
    guard let controller = controller(in: context), !isNameTaken(in: context) else { return nil }
    let applicationScope: RemappingApplicationScope
    switch scopeKind {
    case .global: applicationScope = .global
    case .application: applicationScope = .application(appID: appID)
    }
    let profile = RemappingProfile(
      name: ProfileNameValidation.trimmedName(name(in: context)),
      device: RemappingDeviceScope(vendorID: controller.vendorID, productID: controller.productID),
      applicationScope: applicationScope,
      outputPolicy: outputPolicy,
      bindings: []
    )
    guard (try? profile.validate()) != nil else { return nil }
    return profile
  }

  /// Validation is shown only once a field has been edited and the fields do not make a valid
  /// profile.
  func showsValidation(isValid: Bool) -> Bool { !isValid && self != Self() }
}
