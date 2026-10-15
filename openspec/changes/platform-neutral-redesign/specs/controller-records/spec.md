## ADDED Requirements

### Requirement: Controller knowledge is data

A `Controller` document SHALL describe a controller model completely enough that supporting a new controller whose protocol is a known algorithmic protocol, or fully expressible as data, needs no source change. The repository SHALL contain no controller-specific VID:PID literal, quirk tag or family default in Swift or Python code outside authored data files.

#### Scenario: Add a controller by file

- **WHEN** a user places a valid `Controller` document for a new model in the user controllers folder
- **THEN** the service matches a connected unit of that model and drives it with the protocol the document names

#### Scenario: Literal scan

- **WHEN** the repository check scans Swift and Python sources for controller VID:PID pairs
- **THEN** no hit is outside the allow-list of documented non-controller uses (persona ids, DEXT grant)

### Requirement: Modes and match keys

A `Controller` SHALL list one or more `modes`. Each mode SHALL name a `protocol` with typed `parameters` and one or more match keys: link kind, interface signature, manufacturer string, product string, `bcdDevice` range, and read-only probes.

#### Scenario: One model, two modes

- **WHEN** a record lists a wired mode and a Bluetooth mode and the controller connects over Bluetooth
- **THEN** the Bluetooth mode is selected

### Requirement: Declarative input layout

A mode SHALL be able to declare input fields by report id, bit offset, bit size, signedness, logical range, inversion, trigger rest value, and hat source, for 10 to 16 bit values, 16-bit triggers, more than four axes and extra buttons, using only canonical control ids.

#### Scenario: Twelve-bit stick

- **WHEN** a record declares `LeftStickX` as 12 bits at bit offset 0 of report 1
- **THEN** the parser decodes that field and reports a normalized value from -1 to 1

#### Scenario: Unknown control id

- **WHEN** a record names a control id outside the vocabulary
- **THEN** the record is rejected and listed as a problem

### Requirement: Sessions as data

A mode SHALL be able to declare initialization, keepalive, settle and shutdown steps, vendor control transfers (`bmRequestType`, `bRequest`, `wValue`, `wIndex`, `wLength`), and output templates (fixed bytes, scaling, motor positions, resend interval). Raw bytes SHALL be written as uppercase hex pairs separated by single spaces.

#### Scenario: Gated vendor reads

- **WHEN** a record lists three vendor control reads gated by the manufacturer string "SHANWAN"
- **THEN** the reads run only for a device whose manufacturer string matches, and no other device receives them

#### Scenario: Byte format

- **WHEN** a record contains the bytes `0x1a 2b`
- **THEN** validation fails because the pattern `^[0-9A-F]{2}( [0-9A-F]{2})*$` is not met

### Requirement: Full capability declaration

A `Controller` SHALL declare its controls, sensors, touch surfaces, outputs and battery in full, not as deltas against parser defaults. The parser output for a model SHALL equal its declaration.

#### Scenario: Declaration mismatch

- **WHEN** a parser test emits a control that the record does not declare
- **THEN** the test fails

### Requirement: Facts only

A `Controller` SHALL NOT contain provenance, verification state, confidence or review state. Tuning values (polling interval, queue policy, deadzone) SHALL live in `ControllerPatch` or defaults, not in the hardware description.

#### Scenario: Provenance field

- **WHEN** a record contains a field named `verified`
- **THEN** schema validation rejects it

### Requirement: Layered patches

A `ControllerPatch` SHALL apply with RFC 7396 merge semantics in the order catalog record, built-in patch, package patch, user patch, with the more specific selector (`model`, then `vendorID`/`productID`, then `all`) winning inside one layer.

#### Scenario: User patch wins

- **WHEN** a package patch sets `stickDeadzone` to 0.1 and a user patch sets it to 0.05 for the same model
- **THEN** the effective value is 0.05

#### Scenario: Null deletes

- **WHEN** a patch sets a key to `null`
- **THEN** the effective record has no such key

#### Scenario: All patch reaches only families that read the key

- **WHEN** an `all` patch sets `hidStartupRecoveryRounds` and a record's family does not read that tuning key
- **THEN** that record's effective tuning has no such key, while a `nintendo.switch1` record gets the value

### Requirement: Generated catalog is not hand-edited

Generated records under `Sources/OpenJoystickDriverKit/Resources/Controllers/` SHALL be produced only by `./Scripts/ojd catalog regenerate --write` from authored inputs, and `./Scripts/ojd catalog regenerate --check` SHALL pass on a clean tree.

#### Scenario: Regeneration check

- **WHEN** the check runs after a regenerate
- **THEN** it exits 0
