#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileNameSheet: View {
    let title: String
    let context: ProfileCreationContext
    let onCreate: (RemappingProfile) -> Void
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var fields = ProfileCreationFields()

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(title).font(.headline)
        Form {
          if context.choices.isEmpty {
            Text(OJDLocalized.string("status.connectController"))
              .foregroundColor(Color(NSColor.secondaryLabelColor))
          } else {
            TextField(OJDLocalized.string("common.profileName"), text: nameBinding)
            if let message = nameProblem {
              Text(message).foregroundColor(Color(NSColor.systemRed)).fixedSize(
                horizontal: false,
                vertical: true
              )
            }
            Picker(OJDLocalized.string("common.controller"), selection: controllerBinding) {
              ForEach(context.sections) { section in
                Section(header: Text(section.title)) {
                  ForEach(section.choices) { choice in Text(choice.label).tag(choice.id) }
                }
              }
            }
            Picker(OJDLocalized.string("profiles.target"), selection: $fields.scopeKind) {
              Text(OJDLocalized.string("profiles.targetGlobal")).tag(ProfileScopeKind.global)
              Text(OJDLocalized.string("profiles.targetApplication")).tag(
                ProfileScopeKind.application
              )
            }
            if fields.scopeKind == .application {
              TextField(OJDLocalized.string("profiles.appID"), text: $fields.appID)
            }
            ProfileOutputPolicyView(policy: fields.outputPolicy) { fields.outputPolicy = $0 }
            if fields.showsValidation(isValid: proposedProfile != nil) && nameProblem == nil {
              Text(OJDLocalized.string("profiles.creationValidation"))
                .foregroundColor(Color(NSColor.systemRed)).fixedSize(
                  horizontal: false,
                  vertical: true
                )
            }
          }
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("common.create")) {
            guard let proposedProfile else { return }
            onCreate(proposedProfile)
            presentationMode.wrappedValue.dismiss()
          }.disabled(proposedProfile == nil)
        }
      }.padding(20).frame(width: 420)
    }

    private var proposedProfile: RemappingProfile? { fields.proposedProfile(in: context) }

    private var nameProblem: String? {
      let name = fields.name(in: context)
      if fields.isNameTaken(in: context) { return OJDLocalized.string("error.duplicateProfile") }
      if !name.isEmpty && ProfileNameValidation.trimmedName(name).isEmpty {
        return OJDLocalized.string("capture.profileNameValidation")
      }
      return nil
    }

    private var nameBinding: Binding<String> {
      Binding(
        get: { fields.name(in: context) },
        set: { fields.editedName = $0 }
      )
    }

    private var controllerBinding: Binding<String> {
      Binding(
        get: { fields.controller(in: context)?.id ?? "" },
        set: { fields.selectedControllerID = $0 }
      )
    }
  }

  /// Asks for the name of a copy of a profile; the name starts as the default copy name.
  struct ProfileDuplicateSheet: View {
    let source: RemappingProfile
    let profiles: [RemappingProfile]
    let onDuplicate: (RemappingProfile) -> Void
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var name: String?

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(OJDLocalized.string("common.duplicate")).font(.headline)
        Form {
          TextField(OJDLocalized.string("common.profileName"), text: nameBinding)
          if ProfileNaming.isTaken(shownName, in: profiles) {
            Text(OJDLocalized.string("error.duplicateProfile"))
              .foregroundColor(Color(NSColor.systemRed))
          } else if !shownName.isEmpty && ProfileNameValidation.trimmedName(shownName).isEmpty {
            Text(OJDLocalized.string("capture.profileNameValidation"))
              .foregroundColor(Color(NSColor.systemRed))
          }
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("common.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("common.duplicate")) {
            guard let duplicate else { return }
            onDuplicate(duplicate)
            presentationMode.wrappedValue.dismiss()
          }.disabled(duplicate == nil)
        }
      }.padding(20).frame(width: 420)
    }

    private var shownName: String { name ?? defaultDuplicateName(of: source, in: profiles) }

    private var nameBinding: Binding<String> {
      Binding(get: { shownName }, set: { name = $0 })
    }

    private var duplicate: RemappingProfile? {
      duplicatedProfile(source, named: shownName, in: profiles)
    }
  }

#endif
