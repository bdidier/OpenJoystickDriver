## ADDED Requirements

### Requirement: Guideline compliance

The CLI SHALL follow clig.dev guidelines and Apple command-line conventions: exit codes, `--help` on every command, `--json`, `--plain`, `-q`, `--no-color`, `--no-input`, `--timeout`, errors on standard error with a fix hint, and no prompts when `--no-input` is set.

#### Scenario: Help

- **WHEN** the user runs any command with `--help`
- **THEN** usage, flags and examples print and the exit code is 0

#### Scenario: No input

- **WHEN** a destructive command runs with `--no-input` and no `--force`
- **THEN** it exits non-zero without prompting

### Requirement: OS-neutral vocabulary

Command names, flags, output fields and enum values SHALL use OS-neutral words (`system|ojd`, `input-read`, `input-inject`, `usb-transport`, `transport-extension`, `publisher.kind signed|platform`, `appID`, `meta`, `alt`, `hid|rawUsb|usbExtension`, `osVersion`, `osName`, `systemGamepadAudit`). OS-specific words SHALL appear only in `platform` sub-objects or commands.

#### Scenario: Status output

- **WHEN** the user runs `ojd status --json`
- **THEN** no field outside `platform` contains `macOS`, `Apple`, `DriverKit` or `Bundle`

### Requirement: Command tree

The groups SHALL be `status`, `permission`, `transport-extension`, `service`, `controller`, `virtual`, `profile`, `binding`, `config`, `record`, `mod`, `access`, `setting`, `update`, `log`, `diagnose`, `explain`. `virtual` SHALL include `export-mapping`. `controller` SHALL include `claim <ref>` and `release <ref>` in place of `ownership`.

#### Scenario: Removed command

- **WHEN** the user runs `ojd extension`
- **THEN** the CLI exits non-zero and suggests `transport-extension`

### Requirement: Settings are CLI-reachable

Every GUI setting (launch at login, show in menu bar, update checks, per-event notifications, command-line link) SHALL be a `setting` key readable and writable from the CLI. Settings SHALL live in a layered settings file with its own schema, not in `UserDefaults`.

#### Scenario: Notification toggle

- **WHEN** the user runs `ojd setting set notify.controllerConnected false`
- **THEN** the GUI toggle shows off

### Requirement: Neutral core

The CLI SHALL depend on a platform-neutral core. macOS-only code SHALL sit in a host adapter module the CLI loads through a protocol.

#### Scenario: Import check

- **WHEN** a check lists CLI-target imports
- **THEN** none is a macOS-only module outside the adapter

### Requirement: Single data directory

All stores SHALL resolve their directory through one data-directory port.

#### Scenario: Relocation

- **WHEN** the data directory is overridden by an environment variable
- **THEN** records, profiles, packages, settings and grants all move

### Requirement: Output schemas

Every command's `--json` output SHALL validate against `cli-output.schema.json` and carry `apiVersion` and `kind`.

#### Scenario: Schema test

- **WHEN** the CLI output tests run
- **THEN** each command's output validates
