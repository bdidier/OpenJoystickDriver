import Foundation
import OpenJoystickDriverKit

/// A controller a new profile can target: a connected controller, or a controller model that is
/// not connected. `ojd profile create --controller` accepts both.
struct ProfileControllerChoice: Equatable, Identifiable {
  let id: String
  /// The controller's own name; nil for a model that is not connected.
  let name: String?
  let vendorID: UInt16
  let productID: UInt16

  /// The name in the picker: the controller's name, or its vendor and product identifiers.
  var label: String {
    OJDValue.reported(name).textOrNil
      ?? OJDValue.usbIdentifier(vendorID: vendorID, productID: productID).displayText
  }

  /// The connected controllers, then the models that none of them has: first those of `profiles`,
  /// then those of `catalog`, each ordered by vendor and product.
  static func choices(
    devices: [ApplicationServiceDeviceDescription],
    profiles: [RemappingProfile],
    catalog: [ControllerModelID]
  ) -> [Self] {
    let connected = devices.map {
      Self(
        id: $0.sessionToken.rawValue,
        name: $0.name,
        vendorID: $0.vendorID,
        productID: $0.productID
      )
    }
    var seen = Set(
      connected.map { ControllerModelID(vendorID: $0.vendorID, productID: $0.productID) }
    )
    func models(_ ids: [ControllerModelID]) -> [Self] {
      ids.sorted().compactMap { model in
        guard seen.insert(model).inserted else { return nil }
        return Self(
          id: String(format: "model-%04X-%04X", model.vendorID, model.productID),
          name: nil,
          vendorID: model.vendorID,
          productID: model.productID
        )
      }
    }
    let known = models(
      profiles.map {
        ControllerModelID(vendorID: $0.device.vendorID, productID: $0.device.productID)
      }
    )
    return connected + known + models(catalog)
  }
}

/// What the New Profile sheet knows besides the fields: the controllers it offers and the
/// profiles that already exist.
struct ProfileCreationContext: Equatable {
  let choices: [ProfileControllerChoice]
  let profiles: [RemappingProfile]
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
