/// One HID client's count of input reports the system dropped because the queue between the
/// device and the client was full.
package struct HIDInputDropObservation: Equatable, Sendable {
  package let productName: String
  package let vendorID: Int
  package let productID: Int
  package let droppedReports: Int

  package init(productName: String, vendorID: Int, productID: Int, droppedReports: Int) {
    self.productName = productName
    self.vendorID = vendorID
    self.productID = productID
    self.droppedReports = droppedReports
  }
}
