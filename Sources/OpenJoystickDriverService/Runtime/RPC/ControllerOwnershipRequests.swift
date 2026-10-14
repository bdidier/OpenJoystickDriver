import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// Sets who serves the controller model in the user's record for it. The record watcher then
  /// applies the change to every connected controller of the model without a replug.
  public func setControllerOwnership(
    vendorID: Int,
    productID: Int,
    ownership: ControllerOwnership
  ) async -> ControllerOwnershipResult {
    let nativeGamepadConnected = await connectedDevices().contains {
      $0.vendorID == vendorID && $0.productID == productID
        && $0.physicalOwnership == .nativeGamepad
    }
    return Self.setControllerOwnership(
      vendorID: vendorID,
      productID: productID,
      ownership: ownership,
      nativeGamepadConnected: nativeGamepadConnected
    )
  }

  /// Writes `ownership` to the model's user record in `directory`. A raw-USB family, or a model
  /// macOS does not serve natively, is refused; a model whose record already gives it to OJD
  /// counts as native, because OJD seized a controller macOS would serve.
  static func setControllerOwnership(
    vendorID: Int,
    productID: Int,
    ownership: ControllerOwnership,
    nativeGamepadConnected: Bool,
    directory: URL = ControllerRecordSet.userDirectory
  ) -> ControllerOwnershipResult {
    let records = ControllerRecordSet.load(userDirectory: directory)
    func refused(
      _ failure: ControllerOwnershipFailure,
      _ previous: ControllerOwnership = .macOS,
      detail: String? = nil
    ) -> ControllerOwnershipResult {
      ControllerOwnershipResult(
        ownership: ownership,
        previous: previous,
        file: nil,
        created: false,
        failure: failure,
        detail: detail
      )
    }
    guard let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID) else {
      return refused(.noRecord)
    }
    let identity = ControllerIdentity(vendorID: vendor, productID: product)
    let record = records.records[identity]
    let previous = record?.ownership ?? .macOS
    if record?.usesRawUSB == true { return refused(.rawUSB, previous) }
    guard nativeGamepadConnected || previous == .ojd else { return refused(.notNative, previous) }
    let change: ControllerOwnershipWriter.Change
    do {
      change = try ControllerOwnershipWriter.change(
        identity,
        to: ownership,
        records: records,
        directory: directory
      )
    } catch {
      switch error {
      case .noRecord: return refused(.noRecord, previous)
      case .invalidFile(let problem), .invalidResult(let problem):
        return refused(.invalidRecord, previous, detail: problem)
      }
    }
    var failure: ControllerOwnershipFailure?
    var detail: String?
    do { try ControllerOwnershipWriter.write(change) } catch {
      failure = .persistenceFailed
      detail = error.localizedDescription
    }
    return ControllerOwnershipResult(
      ownership: ownership,
      previous: change.previous,
      file: change.file.path,
      created: change.created,
      failure: failure,
      detail: detail
    )
  }
}
