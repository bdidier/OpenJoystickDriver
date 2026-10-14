## ADDED Requirements

### Requirement: Observed device to link to mode

The service SHALL turn an observed device into a link (kind, access, address) and select a record mode by link kind and match keys. A model SHALL be reachable through several VID:PID pairs and several link kinds.

#### Scenario: Dongle and wired

- **WHEN** the same model attaches once through a dongle and once through USB
- **THEN** each attachment gets its own link and selects the mode that matches its kind

### Requirement: Read-only behavioral probes

A mode SHALL be able to require a probe: a read of a named feature report whose answer, stall or byte pattern must match. A probe SHALL NOT write to the device. A failed or inconclusive probe SHALL select the model's default mode and SHALL NOT disable the controller.

#### Scenario: Same-ID clone

- **WHEN** two units share `054C:0268`, strings and descriptor, and only one answers feature report `0xEF`
- **THEN** each unit is matched to the mode whose probe it satisfies

#### Scenario: Probe stalls unexpectedly

- **WHEN** a probe read stalls on a unit whose record expects an answer
- **THEN** the unit uses the default mode and the log notes the probe result

### Requirement: Extension match list generated from records

The DriverKit extension matching list SHALL be generated from records whose serving route is `ExtensionOwned`. It SHALL contain only IDs in the Apple `transport.usb` grant (`045E:02D1`, `02DD`, `02E3`, `02EA`, `0B00`, `0B0A`, `0B12`).

#### Scenario: Record outside the grant

- **WHEN** a record asks for the extension with an ID outside the grant
- **THEN** `./Scripts/ojd check driverkit` fails and names the record

### Requirement: Connection address is typed

A link address SHALL be one of an IOKit location with optional interface number, a USB service route with service id, or a GATT peripheral UUID. No synthetic location number SHALL stand for a peripheral.

#### Scenario: Switch 2 over Bluetooth LE

- **WHEN** a Switch 2 controller connects over Bluetooth LE
- **THEN** its address is a GATT peripheral UUID

### Requirement: Bluetooth classic pairing host address

The CLI SHALL offer `ojd controller pair --host-address auto` to write the host Bluetooth address into a controller that needs it (DS3). Where the OS refuses pairing, the command SHALL report the OS reason.

#### Scenario: macOS 12 host

- **WHEN** the command runs on a macOS 12 host with a DS3 on USB
- **THEN** the host address is written and the DS3 pairs over Bluetooth
