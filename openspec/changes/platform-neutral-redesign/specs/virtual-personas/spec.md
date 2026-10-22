## ADDED Requirements

### Requirement: Two personas

OJD SHALL provide two virtual personas as bundled `VirtualDevice` records: `Generic` (vendor `1209`, product `4A4F`, a standard HID gamepad) and `SDLCompatible` (vendor `045E`, product `02FD`). Automatic selection SHALL publish `SDLCompatible` when the controller's primary controls fit it and `Generic` otherwise, unless the user selects a persona.

#### Scenario: Fresh install

- **WHEN** a controller is served virtually and the user has set no persona
- **THEN** the virtual device reports `045E:02FD`

#### Scenario: Choose Generic

- **WHEN** the user runs `ojd virtual set generic <ref>`
- **THEN** the virtual device for that controller reports `1209:4A4F`

### Requirement: No Microsoft id outside SDLCompatible

No code, record, sample, test fixture or HIDTool subcommand SHALL use a Microsoft vendor id except the `SDLCompatible` persona record and the seven granted extension IDs. The retired id `4F4A:4449` SHALL NOT remain as a live identity. The SDK sample SHALL use `1209:0001`, which pid.codes reserves for private testing, and no bundled record or persona SHALL use it.

#### Scenario: Scan

- **WHEN** the repository check scans for `045E` outside the allowed files
- **THEN** it finds none

### Requirement: SDLCompatible status

Documentation SHALL state that PCSX2 2.8.2 (SDL 3.4.12) and DuckStation (SDL 3.4.16) map `SDLCompatible` as an Xbox pad with default hints, and that Steam is untested.

#### Scenario: Documentation

- **WHEN** a reader opens the persona page
- **THEN** it states the SDL versions tested and that Steam is untested

### Requirement: Persona document

A `VirtualDevice` SHALL hold `layout`, `transport`, identity (`vendorID`, `productID`, `version`, `productName`, `manufacturer`) and `labels`, and `match` by model or port. Persona ids on the CLI are lowercase kebab-case forms of the enum values.

#### Scenario: Invalid persona id

- **WHEN** the user passes an unknown persona id
- **THEN** the CLI exits non-zero and lists the valid ids
