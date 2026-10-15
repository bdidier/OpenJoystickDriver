import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

/// The controller detail shows the serving route `ojd controller show` prints as `serving.route`.
@MainActor
struct ServingRouteLabelTests {
  private static func key(for route: ServingRoute) -> String {
    switch route {
    case .nativePassThrough: "controllers.serving.nativePassThrough"
    case .virtualHid: "controllers.serving.virtualHid"
    case .extensionOwned: "controllers.serving.extensionOwned"
    case .outputDisabled: "controllers.serving.outputDisabled"
    }
  }

  @Test(arguments: ServingFixture.all)
  func detailLabelNamesTheRouteOfTheServingPolicy(_ fixture: ServingFixture) {
    let decided = ServingPolicy.decision(fixture.input).route
    #expect(fixture.device.servingRouteLabel == OJDLocalized.string(Self.key(for: decided)))
  }

  @Test
  func everyRouteHasItsOwnLocalizedLabel() {
    let labels = ServingFixture.all.map { fixture in
      Self.key(for: ServingPolicy.decision(fixture.input).route)
    }
    #expect(Set(labels).count == 4)
    for key in Set(labels) { #expect(OJDLocalized.string(key) != key) }
  }
}
