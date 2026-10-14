## ADDED Requirements

### Requirement: Two personas

OJD SHALL provide two virtual personas as bundled `VirtualDevice` records: `Generic` (vendor `1209`, product `4A4F`, a standard HID gamepad) and `SdlCompatible` (vendor `045E`, product `02FD`). The default persona SHALL be `Generic` for every model and app unless the user selects otherwise.

#### Scenario: Fresh install

- **WHEN** a controller is served virtually and the user has set no persona
- **THEN** the virtual device reports `1209:4A4F`

#### Scenario: Opt in

- **WHEN** the user runs `ojd virtual set sdl-compatible <ref>`
- **THEN** the virtual device for that controller reports `045E:02FD`

### Requirement: No Microsoft id outside SdlCompatible

No code, record, sample, test fixture or HIDTool subcommand SHALL use a Microsoft vendor id except the `SdlCompatible` persona record and the seven granted extension IDs. The retired id `4F4A:4449` and the sample id `1209:0001` SHALL NOT remain as live identities.

#### Scenario: Scan

- **WHEN** the repository check scans for `045E` outside the allowed files
- **THEN** it finds none

### Requirement: SdlCompatible status

Until a hardware-evidenced fix exists, documentation SHALL state that `SdlCompatible` is not listed by SDL 3.4.x with default hints. After a fix, the hardware check SHALL show SDL listing it with default hints.

#### Scenario: Documentation

- **WHEN** a reader opens the persona page
- **THEN** it states the SDL limitation and the version it was observed on

### Requirement: Persona document

A `VirtualDevice` SHALL hold `layout`, `transport`, identity (`vendorID`, `productID`, `version`, `productName`, `manufacturer`) and `labels`, and `match` by model or port. Persona ids on the CLI are lowercase kebab-case forms of the enum values.

#### Scenario: Invalid persona id

- **WHEN** the user passes an unknown persona id
- **THEN** the CLI exits non-zero and lists the valid ids
