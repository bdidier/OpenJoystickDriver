## MODIFIED Requirements

### Requirement: REQ-24 Original Xbox One controller is listed

The USB transport adapter MUST take the identity of an XboxUSBDevice service (`idVendor`, `idProduct`, `locationID`, and the strings) from its parent `IOUSBHostDevice`, so that an original Xbox One controller (`045E:02D1`, model 1537) is listed by `ojd controller list` and bound to `XboxGIP` when the extension is active.
The route of the controller is `ExtensionOwned`, set by its record, and the extension match list that holds `045E:02D1` is generated from the records with that route. `docs/testing/xbox-one-02d1.md` MUST record the evidence and say that the fix is not verified on hardware.

#### Scenario: Extension active

- **WHEN** a `045E:02D1` controller is connected and the XboxUSBDevice extension is active
- **THEN** the transport reads its identity from the parent `IOUSBHostDevice` and `DeviceManager` claims it on interface 0 for `XboxGIP` (`dextServiceTakesIdentityFromParentUSBDevice`, `dextRouteServiceIsClaimedOnInterfaceZero`)
- **AND** the listing is not confirmed on hardware

#### Scenario: Service without a parent

- **WHEN** an extension service has no parent `IOUSBHostDevice` and no scalar `idVendor` and `idProduct` of its own
- **THEN** the transport lists no device for it (`dextServiceWithoutParentYieldsNoDevice`)

## ADDED Requirements

### Requirement: REQ-25 A device held by another owner is named, not retried

When the host refuses the configuration descriptor read of a raw-USB device with `accessDenied`, `DeviceManager` MUST acknowledge the service and leave it unclaimed, record it as unbound with the reason `DeviceInUse`, and log the refusal once, naming the exclusive owner the host reports (`UsbExclusiveOwner`). The poll MUST NOT read the descriptor again until the service re-enumerates or the host stops reporting the owner it reported at the refusal. A refusal with no reported owner, or an owner that cannot be read, waits for re-enumeration. The Controllers page and `ojd status` MUST show the sentence `ui.controllers.deviceInUse` for the device.

#### Scenario: Another program holds the controller

- **WHEN** a raw-USB controller's descriptor read is refused with `accessDenied` and the host reports an exclusive owner
- **THEN** the descriptor is read once across later polls and the log line appears once (`deniedDescriptorReadIsAcknowledgedAndReadOnce`, `theDetectionLoopReadsAHeldDeviceOnceAcrossPolls`)
- **AND** the device is listed with the reason (`controllersPageListsADeviceHeldByAnotherProgramWithItsReason`, `aDeviceHeldByAnotherProgramIsExplainedInHumanOutputOnly`)

#### Scenario: The owner releases the device

- **WHEN** the host stops reporting the owner of a held service
- **THEN** the service is admitted again on the next poll (`heldServiceIsAdmittedAgainOnlyWhenItsHolderGoesAway`)
