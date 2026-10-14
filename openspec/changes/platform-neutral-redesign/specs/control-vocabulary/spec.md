## ADDED Requirements

### Requirement: One position-based vocabulary

Records, profiles, CLI output, the endpoint and the GUI SHALL use one control vocabulary whose ids name positions, not labels: `South`, `East`, `West`, `North`, `LeftShoulder`, `RightShoulder`, `LeftTrigger`, `RightTrigger`, `Back`, `Start`, `LeftStickClick`, `RightStickClick`, `DpadUp`, `DpadDown`, `DpadLeft`, `DpadRight`, `Guide`, `Capture`, `Microphone`, `TouchpadClick`, paddles, auxiliaries and the four stick axes. `ControlID` and `RemappingButton` SHALL NOT exist.

#### Scenario: Label does not rename

- **WHEN** a PlayStation record labels `South` as "Cross"
- **THEN** every document still uses `South`

#### Scenario: Removed ids

- **WHEN** a document uses `Share` or `Options`
- **THEN** it is rejected

### Requirement: Crosswalk

Documentation SHALL provide a crosswalk from each id to W3C Gamepad index, SDL3 name, Linux evdev code, HID page and usage, and Apple GameController element. The crosswalk SHALL be documentation, not schema aliases.

#### Scenario: Lookup

- **WHEN** a reader looks up `Back`
- **THEN** the table shows W3C 8, SDL BACK, BTN_SELECT, and ButtonOptions

### Requirement: Axis direction and values

Y axes SHALL be positive down. Triggers SHALL be 0 to 1. Stick axes SHALL be -1 to 1.

#### Scenario: Stick up

- **WHEN** the stick is pushed up
- **THEN** the Y value is negative

### Requirement: Rumble and keyboard vocabulary

Rumble actuators SHALL be `LowFrequency`, `HighFrequency`, `LeftTrigger`, `RightTrigger`, `LeftHaptic`, `RightHaptic`. Profile keyboard outputs SHALL use W3C `KeyboardEvent.code` values.

#### Scenario: Key code

- **WHEN** a profile maps a button to the ISO section key
- **THEN** it writes `IntlBackslash`
