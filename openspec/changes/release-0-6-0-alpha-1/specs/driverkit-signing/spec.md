## Purpose

The signing checks and the DriverKit build accept the provisioning profiles that grant the host user-client access to XboxUSBDevice.

## ADDED Requirements

### Requirement: REQ-25 Signing matches the regenerated profiles

`./Scripts/ojd signing doctor` MUST pass with the host profiles that the maintainer regenerates with `com.apple.developer.driverkit.userclient-access` for `com.openjoystickdriver.XboxUSBDevice`.

#### Scenario: Regenerated host profiles installed

- **WHEN** the maintainer runs `./Scripts/ojd signing doctor` with the regenerated host profiles
- **THEN** it prints `[OK] host profile grants user-client access to com.openjoystickdriver.XboxUSBDevice` and exits 0

### Requirement: REQ-26 A host profile that grants more user-client IDs is accepted

`signing configure`, `signing doctor`, and the DriverKit build MUST accept a host profile whose `userclient-access` list includes `com.openjoystickdriver.XboxUSBDevice` among other bundle IDs, and the signed app MUST still claim exactly `com.openjoystickdriver.XboxUSBDevice` from `Host.entitlements`.

#### Scenario: Profile lists XboxUSBDevice and VirtualHIDDevice

- **WHEN** the host profile's `userclient-access` is `[XboxUSBDevice, VirtualHIDDevice]`
- **THEN** `signing configure`, `signing doctor`, and the DriverKit build accept it
- **AND** the signed app claims exactly `com.openjoystickdriver.XboxUSBDevice`

#### Scenario: Wildcard or any-access grant

- **WHEN** the host profile's value is `"*"`, holds a non-string item, or the profile uses `allow-any-userclient-access`
- **THEN** the checks refuse it
