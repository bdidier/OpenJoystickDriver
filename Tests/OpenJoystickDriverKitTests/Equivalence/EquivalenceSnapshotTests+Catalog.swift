import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverUSB

/// Snapshots the behavior the bundled catalog drives today: each record's resolved runtime
/// behavior and the route that reaches its controller.
struct EquivalenceSnapshotCatalogTests {
  static let records = ControllerRecordSet.bundled.records.values.sorted {
    $0.model < $1.model
  }

  static func title(_ record: ControllerRecord) -> String {
    EquivalenceSnapshotStore.recordTitle(
      vendorID: record.model.vendorID,
      productID: record.model.productID
    )
  }

  private static let indexHeader = """
    # Effective behavior of each catalog record as resolved values: startup, keep-alive and
    # activation writes as hex, tuning and session timings as numbers, capabilities as sorted
    # sets. Enum-like fields use the explicit labels in EquivalenceSnapshotTests+CatalogLabels.
    # The parameters= line is the one exception: it lists the record's protocol parameters as
    # name=value entries in the record's own spelling, because parameters that only steer report
    # decoding have no resolved value to print here. The parsed-frames snapshot shows their
    # effect for the records with sample reports.

    """

  /// How the controller is reached today, decided by the real transport selection: a device the
  /// raw-USB provider would list on the IOUSBHost route is `raw-access`, one it would leave to
  /// the signed USB extension is `extension`, and anything else stays with the system HID stack.
  private static func route(_ record: ControllerRecord) -> String {
    let models = Set(ProtocolDriverRegistry().rawUSBModels)
    let model = record.model
    func selects(_ route: USBTransportRoute) -> Bool {
      let device = USBTransportDevice(
        route: route,
        serviceID: 1,
        vendorID: model.vendorID,
        productID: model.productID,
        locationID: 1
      )
      return !OpenJoystickDriverUSBTransportProvider.selectDevices(
        direct: route == .ioUSBHost ? [device] : [],
        driverKit: route == .usbDriverKit ? [device] : [],
        supportedRawUSBModels: models,
        requiredDriverKitModels: OpenJoystickDriverUSBTransportProvider.driverKitRequiredModels
      ).isEmpty
    }
    if selects(.ioUSBHost) { return "raw-access" }
    if selects(.usbDriverKit) { return "extension" }
    return "system ownership=\(label(record.ownership))"
  }

  @Test
  func catalogIndexMatchesSnapshot() throws {
    let sections = Self.records.map { (title: Self.title($0), lines: Self.profileLines($0)) }
    let rendered = EquivalenceSnapshotStore.render(sections, header: Self.indexHeader)
    #expect(try EquivalenceSnapshotStore.verify(rendered, named: "catalog-index.txt") == nil)
  }

  @Test
  func recordRoutesMatchSnapshot() throws {
    let sections = Self.records.map { (title: Self.title($0), lines: [Self.route($0)]) }
    let rendered = EquivalenceSnapshotStore.render(sections)
    #expect(try EquivalenceSnapshotStore.verify(rendered, named: "record-routes.txt") == nil)
  }
}
