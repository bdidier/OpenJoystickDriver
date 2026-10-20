## ADDED Requirements

### Requirement: One serving route per controller

Each controller SHALL have exactly one serving route: `NativePassThrough` (with an allowance), `VirtualHID` (with a persona), `ExtensionOwned`, or `OutputDisabled`. A single pure policy SHALL decide it from the record, the link, the user setting and the controller's allowance. It SHALL NOT take a per-app input: a virtual HID device is system-wide, and macOS does not tell the service which app reads it. No other component SHALL decide it.

#### Scenario: Same inputs

- **WHEN** the policy is called twice with equal inputs
- **THEN** it returns equal routes

#### Scenario: Passthrough profile on native controller

- **WHEN** a controller served natively has a passthrough profile and the user sets `server` to `ojd`
- **THEN** the route becomes `VirtualHID` and a virtual gamepad appears

### Requirement: Ownership vocabulary

The user-facing setting SHALL be `server: system | ojd`. Records, CLI and GUI SHALL use these values.

#### Scenario: CLI toggle

- **WHEN** the user runs `ojd controller claim <ref>`
- **THEN** the setting is stored and the route is re-evaluated without reconnecting

### Requirement: Suspension survives route changes

A suspended controller SHALL stay suspended when its route is re-evaluated.

#### Scenario: Toggle while suspended

- **WHEN** a suspended controller's `server` setting changes
- **THEN** it remains suspended
