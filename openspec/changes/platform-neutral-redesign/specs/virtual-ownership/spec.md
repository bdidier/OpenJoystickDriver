## MODIFIED Requirements

### Requirement: REQ-18 Ownership toggle on the command line

`ojd controller claim CONTROLLER [--dry-run] [--json]` and `ojd controller release CONTROLLER [--dry-run] [--json]` MUST set who serves a controller model that the system supports natively: `release` leaves it to the system, `claim` makes OJD seize it and publish its own virtual gamepad, with the same effect as a record `server` of `System` or `OJD`.

#### Scenario: Switch to virtual

- **WHEN** the user runs `ojd controller claim CONTROLLER` for a natively supported model, or for a model whose record already says `OJD`
- **THEN** OJD seizes the controller and publishes its own virtual gamepad, as a record `server` of `OJD` does

#### Scenario: Switch to native

- **WHEN** the user runs `ojd controller release CONTROLLER`
- **THEN** OJD leaves the controller to the system, as a record `server` of `System` does

### Requirement: REQ-19 Ownership toggle in the app

The app MUST show the current server of each connected controller that the system supports natively, or whose record already says `OJD`, and that is not a raw-USB controller, in the **Served by** picker of the Controllers detail, and MUST let the user switch it between **macOS (native)** and **OpenJoystickDriver (virtual)**.

#### Scenario: Controller detail

- **WHEN** the user opens the detail of a connected controller that the system supports natively
- **THEN** the app shows its current server in the **Served by** picker and lets the user switch between **macOS (native)** and **OpenJoystickDriver (virtual)**

### Requirement: REQ-20 Virtual ownership publishes a virtual gamepad

A controller served by OJD MUST get a published virtual gamepad that games see, with the persona the user chose and `Generic` by default, also when its active profile has `virtualGamepad: passthrough` and no bindings, and the controller's pipeline MUST dispatch each changed report to the virtual device without a remapping route, where the same controller left to the system dispatches none.

#### Scenario: Passthrough profile

- **WHEN** a controller served by OJD has an active profile with `virtualGamepad: passthrough` and no bindings
- **THEN** games see a published virtual gamepad that follows each changed report
- **AND** the pipeline dispatches each changed report with no remapping route, and the same controller left to the system dispatches none (`anOJDOwnedNativeModelDispatchesEachChangedReportWithoutARoute`)

### Requirement: REQ-21 Ownership persists and applies without replugging

A server choice MUST persist across service and app restarts, MUST apply to a connected controller without unplugging it, and `ojd controller show` MUST report the server and where it came from. The single serving policy re-evaluates the route of the controller, and a suspended controller stays suspended.

#### Scenario: Connected controller

- **WHEN** the user changes the server of a connected controller
- **THEN** the change applies without unplugging it
- **AND** a suspended controller stays suspended

#### Scenario: Restart

- **WHEN** the service and the app restart
- **THEN** the choice is kept

#### Scenario: Show the source

- **WHEN** the user runs `ojd controller show CONTROLLER`
- **THEN** the output reports the `server` (`System` or `OJD` with `--json`, `system` or `ojd` otherwise) and its `serverSource` (the record layer that set `server`: `Bundled`, `Package`, `Global` or `User`, or `Default` when no record sets it)

### Requirement: REQ-22 Raw-USB families refuse the toggle

`ojd controller claim` and `ojd controller release` MUST refuse a controller whose record route is `ExtensionOwned` or raw access, such as `XboxGIP`, or one that the system does not support natively, with an error code that names why. The refusal is computed from the route of the record, not from a family list in code.

#### Scenario: Raw-USB family

- **WHEN** the user runs `ojd controller claim` on an `XboxGIP` controller
- **THEN** the command fails with E2023 and names the raw-USB family as the reason

#### Scenario: Not natively supported

- **WHEN** the controller is not supported natively by the system
- **THEN** the command fails with E2023 and names that reason

#### Scenario: No record for the model

- **WHEN** no controller record exists for the controller's model
- **THEN** the command fails with E2023 and names that reason
