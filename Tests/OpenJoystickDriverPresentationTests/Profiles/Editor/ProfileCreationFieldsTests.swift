import Testing

@testable import OpenJoystickDriverPresentation

struct ProfileCreationFieldsTests {
  @Test
  func validationIsHiddenUntilAFieldIsEdited() {
    let initial = ProfileCreationFields.initial(name: "", device: nil)
    #expect(!initial.showsValidation(comparedTo: initial, isValid: false))

    var edited = initial
    edited.name = "Racing"
    #expect(edited.showsValidation(comparedTo: initial, isValid: false))
    #expect(!edited.showsValidation(comparedTo: initial, isValid: true))
  }
}
