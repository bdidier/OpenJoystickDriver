## ADDED Requirements

### Requirement: Protocol descriptions are data

Each protocol family SHALL have a description under `Resources/Protocols/` that holds its defaults (output behavior, capabilities, tuning). Driver code SHALL read these values and SHALL NOT hold a copy.

#### Scenario: Family default changes

- **WHEN** the default rumble resend interval of a family is edited in its description
- **THEN** every record of that family uses the new value without a code change

### Requirement: Typed parameters replace quirk tags

A protocol SHALL accept typed parameters declared in its description. The `ControllerQuirk` tag set SHALL NOT exist. Each former tag SHALL map to a protocol id, a typed parameter, or an input usage map.

#### Scenario: Switch 2 layout

- **WHEN** a record selects protocol `nintendo.switch2` with `layout: JoyConLeft`
- **THEN** the driver uses the left Joy-Con layout

#### Scenario: Unknown parameter

- **WHEN** a record gives a parameter the protocol does not declare
- **THEN** the record is rejected

### Requirement: Code keeps only algorithms

GIP authentication, Switch subcommands, Sony CRC, the Steam protocol and the descriptor interpreters SHALL remain code. Magic bytes inside those algorithms MAY remain in code. Any controller-specific byte sequence outside an algorithm SHALL be in a record.

#### Scenario: Equivalence

- **WHEN** the equivalence harness builds the driver for every bundled record before and after the change
- **THEN** driver type and configuration are equal for all 696 records, or the difference is listed and accepted

### Requirement: Hid usage maps

A record SHALL be able to remap HID usages to canonical controls (replacing the tags `wr007`, `scuf-envision`, `z-rz-brake-left`, `dragonrise`).

#### Scenario: Swapped trigger axes

- **WHEN** a record maps usage Z to `RightTrigger`
- **THEN** a report with Z at maximum yields `RightTrigger` 1.0
