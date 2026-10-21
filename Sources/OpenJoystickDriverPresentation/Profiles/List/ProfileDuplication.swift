import Foundation
import OpenJoystickDriverKit

enum ProfileNameValidation {
  static func trimmedName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// What the Duplicate sheet starts with: the source's name followed by the copy marker, made free
/// of the names `profiles` already have.
func defaultDuplicateName(of source: RemappingProfile, in profiles: [RemappingProfile]) -> String {
  ProfileNaming.availableName(
    OJDLocalized.formatted("profiles.copyName", source.name),
    in: profiles
  )
}

/// A new profile with `source`'s content under `name`, or nil when the name is taken among
/// `profiles` or the copy is not a valid profile.
func duplicatedProfile(
  _ source: RemappingProfile,
  named name: String,
  in profiles: [RemappingProfile]
) -> RemappingProfile? {
  guard !ProfileNaming.isTaken(name, in: profiles) else { return nil }
  let copy = RemappingProfile(
    name: ProfileNameValidation.trimmedName(name),
    device: source.device,
    applicationScope: source.applicationScope,
    outputPolicy: source.outputPolicy,
    physicalColor: source.physicalColor,
    motionTuning: source.motionTuning,
    gyroOutput: source.gyroOutput,
    joyConPair: source.joyConPair,
    stickMappings: source.stickMappings,
    triggerMappings: source.triggerMappings,
    touchMappings: source.touchMappings,
    bindings: source.bindings,
    chords: source.chords,
    sequences: source.sequences,
    layers: source.layers
  )
  return (try? copy.validate()) == nil ? nil : copy
}
