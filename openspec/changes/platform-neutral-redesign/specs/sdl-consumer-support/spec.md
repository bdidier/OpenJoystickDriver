## ADDED Requirements

### Requirement: Published SDL mapping

OJD SHALL publish an SDL mapping for the `Generic` persona with the CRC-less GUID `03000000091200004f4a000008040000`. `ojd virtual show --json` SHALL include `sdl.guid` and `sdl.mapping`, and `ojd virtual export-mapping --format sdl` SHALL write the mapping line to standard output or `--output`.

#### Scenario: Export

- **WHEN** the user runs `ojd virtual export-mapping --format sdl`
- **THEN** the output is one valid SDL mapping line for the Generic persona

#### Scenario: SDL applies it

- **WHEN** an SDL 3 program loads the line with the Generic persona connected
- **THEN** SDL reports a gamepad with all axes at 0 at rest

### Requirement: Mapping reaches launched apps

For an application that OJD launches, OJD SHALL set the SDL mapping environment so the app sees a gamepad without user setup.

#### Scenario: Launch

- **WHEN** a user starts an app through OJD with a Generic persona controller
- **THEN** the app's SDL enumeration reports a gamepad

### Requirement: W3C description

`ojd virtual show --json` SHALL include a `w3c` object describing the persona's buttons and axes, and `export-mapping --format w3c` SHALL write it.

#### Scenario: Format

- **WHEN** the user exports `--format w3c`
- **THEN** the output validates against the `VirtualDevice` export schema

### Requirement: Button and axis directions confirmed

The mapping SHALL ship only after a hardware check records that each button and axis direction matches by real presses.

#### Scenario: Press check

- **WHEN** the maintainer presses each control and reads SDL events
- **THEN** each control reports the mapped SDL name and direction

### Requirement: Wine, CrossOver and browsers documented

Documentation SHALL state, per persona, what SDL, GameController, Wine/CrossOver and browsers see, marking any entry not yet verified on hardware.

#### Scenario: Unverified entry

- **WHEN** the browser entry has no hardware record
- **THEN** the page marks it unverified

### Requirement: Upstream submission is separate

Tasks SHALL NOT submit the mapping to SDL_GameControllerDB or SDL upstream.

#### Scenario: Task list

- **WHEN** the task list is read
- **THEN** it has no submission task and names the decision as the user's
