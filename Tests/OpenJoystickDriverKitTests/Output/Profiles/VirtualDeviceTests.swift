import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualDeviceTests {
  private static let header = #""apiVersion":"openjoystickdriver/v1alpha1","kind":"VirtualDevice""#

  @Test
  func theBundledRecordsDefineBothPersonasWithTheirIdentities() throws {
    let generic = try #require(VirtualDevice.definition(of: .generic).profile)
    #expect((generic.vendorID, generic.productID) == (0x1209, 0x4A4F))
    let sdl = try #require(VirtualDevice.definition(of: .sdlCompatible).profile)
    #expect((sdl.vendorID, sdl.productID) == (0x045E, 0x02FD))
  }

  @Test
  func genericIsTheDefaultPersona() {
    #expect(VirtualHIDProfileID.default == .generic)
  }

  @Test(arguments: [
    #"{"apiVersion":"openjoystickdriver/v2","kind":"VirtualDevice","persona":"Generic"}"#,
    #"{"kind":"VirtualDevice","persona":"Generic"}"#,
    #"{"apiVersion":"openjoystickdriver/v1alpha1","kind":"Persona","persona":"Generic"}"#,
    #"{"apiVersion":"openjoystickdriver/v1alpha1","persona":"Generic"}"#,
  ])
  func aBadHeaderIsRefusedWithE5001(document: String) {
    let problem = #expect(throws: DocumentHeaderProblem.self) {
      try VirtualDevice.decode(Data(document.utf8))
    }
    #expect(problem?.code == .unsupportedAPIVersion)
    #expect(problem?.description.hasPrefix("E5001") == true)
  }

  @Test
  func aDocumentWithAnUnknownPersonaIsRefused() {
    let document = "{\(Self.header),\"persona\":\"hid-generic\"}"
    #expect(throws: ControllerRecordProblem.self) {
      try VirtualDevice.decode(Data(document.utf8))
    }
  }
}
