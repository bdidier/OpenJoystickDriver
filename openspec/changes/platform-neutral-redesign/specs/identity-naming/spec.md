## ADDED Requirements

### Requirement: One name per identity concept

The code SHALL use these types and no others for these concepts: `ControllerModelID`, `ControllerHardwareIdentity`, `ControllerConnectionAddress`, `LogicalControllerID`, `ControllerSessionToken`, `ControllerPortKey`, `ControllerReference`. `DeviceIdentifier`, `ControllerIdentity`, `UnitIdentity`, `ControllerSelection`, `ControllerSelector`, `RuntimeDeviceSelector`, `RecordIdentity`, `OJDControllerRecordIdentity` and `PhysicalHIDIdentity` SHALL NOT exist.

#### Scenario: Symbol search

- **WHEN** a check searches Sources and Tests for a removed name
- **THEN** it finds none

### Requirement: No aliases

Renamed types, parameters, keys and CLI words SHALL NOT keep aliases, typealiases or deprecated forwarding.

#### Scenario: Old CLI word

- **WHEN** the user runs a command with an old word such as `ownership native`
- **THEN** the CLI rejects it with the same error and usage text as any other unknown word, and names no replacement

### Requirement: One reference parser

`ControllerReference` SHALL be parsed by one parser used by the CLI, GUI and RPC, accepting a session token, a port key or a model id.

#### Scenario: Ambiguous model

- **WHEN** a model id matches two connected units
- **THEN** the parser reports both and asks for a session token or port key

### Requirement: Self-descriptive names

New and renamed constructs, parameters and members SHALL have self-descriptive idiomatic names.

#### Scenario: Review

- **WHEN** a reviewer finds a name that needs a comment to explain its meaning
- **THEN** the change is not approved until it is renamed

### Requirement: Stored identity strings

Stored `U-` and `E-` identifier strings MAY change format. Files written by 0.5.x SHALL NOT be read.

#### Scenario: Old port key

- **WHEN** a 0.5.x file holds a `U-...` key
- **THEN** it is rejected as a document with no supported header
