# virtual-ownership Specification

## Purpose

The ownership toggle lets the user choose whether macOS or OJD serves a controller that macOS supports natively, from the command line or the app.

## Requirements

### Requirement: REQ-18 Ownership toggle on the command line

`ojd controller ownership CONTROLLER native|virtual [--dry-run] [--json]` MUST set who serves a controller model that macOS supports natively: `native` leaves it to macOS, and `virtual` makes OJD seize it and publish its own virtual gamepad, with the same effect as a record `ownership` of `macos` or `ojd`.

#### Scenario: Switch to virtual

- **WHEN** the user runs `ojd controller ownership CONTROLLER virtual` for a natively supported model, or for a model whose record already says `ojd`
- **THEN** OJD seizes the controller and publishes its own virtual gamepad, as a record `ownership` of `ojd` does

#### Scenario: Switch to native

- **WHEN** the user runs `ojd controller ownership CONTROLLER native`
- **THEN** OJD leaves the controller to macOS, as a record `ownership` of `macos` does

### Requirement: REQ-19 Ownership toggle in the app

The app MUST show the current ownership of each connected controller that macOS supports natively, or whose record already says `ojd`, and that is not a raw-USB controller, and MUST let the user switch it between native and virtual.

#### Scenario: Controller detail

- **WHEN** the user opens the detail of a connected controller that macOS supports natively
- **THEN** the app shows its current ownership and lets the user switch between native and virtual

### Requirement: REQ-20 Virtual ownership publishes a virtual gamepad

A controller set to virtual MUST get a published virtual gamepad that games see, also when its active profile has `virtualGamepad: passthrough` and no bindings, and the controller's pipeline MUST dispatch each changed report to the virtual device without a remapping route, where the same controller left to macOS dispatches none.

#### Scenario: Passthrough profile

- **WHEN** a controller set to virtual has an active profile with `virtualGamepad: passthrough` and no bindings
- **THEN** games see a published virtual gamepad that follows each changed report
- **AND** the pipeline dispatches each changed report with no remapping route, and the same controller left to macOS dispatches none (`anOJDOwnedNativeModelDispatchesEachChangedReportWithoutARoute`)

### Requirement: REQ-21 Ownership persists and applies without replugging

An ownership choice MUST persist across service and app restarts, MUST apply to a connected controller without unplugging it, and `ojd controller show` MUST report the ownership and where it came from.

#### Scenario: Connected controller

- **WHEN** the user changes the ownership of a connected controller
- **THEN** the change applies without unplugging it

#### Scenario: Restart

- **WHEN** the service and the app restart
- **THEN** the choice is kept

#### Scenario: Show the source

- **WHEN** the user runs `ojd controller show CONTROLLER`
- **THEN** the output reports the ownership choice (`native` or `virtual`) and its source (the record layer that set `ownership`, such as `bundled`, `package`, or `user`, or `default` when no record sets it)

### Requirement: REQ-22 Raw-USB families refuse the toggle

`ojd controller ownership` MUST refuse a controller of a raw-USB family, such as `xbox.gip`, or one that macOS does not support natively, with an error code that names why.

#### Scenario: Raw-USB family

- **WHEN** the user runs `ojd controller ownership` on an `xbox.gip` controller
- **THEN** the command fails with E2023 and names the raw-USB family as the reason

#### Scenario: Not natively supported

- **WHEN** the controller is not supported natively by macOS
- **THEN** the command fails with E2023 and names that reason

#### Scenario: No record for the model

- **WHEN** no controller record exists for the controller's model
- **THEN** the command fails with E2023 and names that reason
