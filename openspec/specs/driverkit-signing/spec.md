# driverkit-signing Specification

## Purpose

The signing checks and the DriverKit build accept the provisioning profiles that grant the host user-client access to XboxUSBDevice.

## Requirements

### Requirement: REQ-25 Signing matches the regenerated profiles

`./Scripts/ojd signing configure` MUST accept the host profiles that the maintainer regenerates with `com.apple.developer.driverkit.userclient-access` for `com.openjoystickdriver.XboxUSBDevice`.

#### Scenario: Regenerated host profiles installed

- **WHEN** the maintainer runs `./Scripts/ojd signing configure` with the regenerated host profiles
- **THEN** it exits 0

### Requirement: REQ-26 A host profile that grants more user-client IDs is accepted

`signing configure` and the DriverKit build MUST accept a host profile whose `userclient-access` list includes `com.openjoystickdriver.XboxUSBDevice` among other bundle IDs, and the signed app MUST still claim exactly `com.openjoystickdriver.XboxUSBDevice` from `Host.entitlements`.

#### Scenario: Profile lists XboxUSBDevice and VirtualHIDDevice

- **WHEN** the host profile's `userclient-access` is `[XboxUSBDevice, VirtualHIDDevice]`
- **THEN** `signing configure` and the DriverKit build accept it
- **AND** the signed app claims exactly `com.openjoystickdriver.XboxUSBDevice`

#### Scenario: Wildcard or any-access grant

- **WHEN** the host profile's value is `"*"`, holds a non-string item, or the profile uses `allow-any-userclient-access`
- **THEN** the checks refuse it

#### Scenario: Development profile without the grant

- **WHEN** a development host profile has no `userclient-access` for `com.openjoystickdriver.XboxUSBDevice`, or lists only other bundle IDs
- **THEN** `signing configure` accepts it and the development build omits the extension
- **AND** a release host profile without the grant is refused
