## Purpose

Mod packages let users install controller records, remapping profiles, and personas as one folder under `Packages/`, served read-only beside their own files and managed with `ojd mod`.

## ADDED Requirements

### Requirement: REQ-1 Read-only package profiles

The service MUST load the profiles of installed packages read-only: a package profile MUST be activatable, and `update`, `delete`, `importProfile`, and a `create` with a package profile's id MUST fail with E3029 `packageProfileReadOnly` before the library is changed.

#### Scenario: Package profile is activated

- **WHEN** the user selects a profile that an installed package provides
- **THEN** the service activates it

#### Scenario: Package profile is changed

- **WHEN** a client calls `update`, `delete`, or `importProfile` on a package profile, or `create` with a package profile's id
- **THEN** the call fails with E3029 `packageProfileReadOnly`
- **AND** the profile library on disk is unchanged

### Requirement: REQ-2 Profile clash rule

When a package profile has the id or the case-insensitive name of a user profile, the user profile MUST win, and among packages the first by package name and then by manifest order MUST win.

#### Scenario: User profile shadows a package profile by name only

- **WHEN** a user profile has the case-insensitive name of a package profile and a different id
- **THEN** the service serves the user profile and not the package profile

#### Scenario: Two packages share a profile name

- **WHEN** two installed packages hold a profile with the same name
- **THEN** the service serves the profile of the package that sorts first by package name

### Requirement: REQ-3 Package profiles never reach the persisted state

`replace`, validation, the profile count limit, recovery, and rollback of `RemappingProfileLibrary` MUST NOT write, delete, or count a package profile file.

#### Scenario: Library replace and restore

- **WHEN** the library runs `replace` or `restore`
- **THEN** every file under `Packages/` is byte-equal to its state before

#### Scenario: Profile count limit

- **WHEN** the library checks the profile count limit
- **THEN** it counts only user profiles

### Requirement: REQ-4 Snapshot lists package profiles

`ApplicationServiceRemappingSnapshotPayload` MUST carry `packageProfiles`, a list of `{profileID, package}`, decoded with a default of an empty list when the key is missing.

#### Scenario: Snapshot with a package profile

- **WHEN** a package profile is served
- **THEN** the remapping snapshot lists `{profileID, package}` for it

#### Scenario: Older payload without the key

- **WHEN** a snapshot payload without `packageProfiles` is decoded
- **THEN** `packageProfiles` is an empty list

### Requirement: REQ-5 Service reloads package profiles

The running service MUST reload the remapping profiles within its watcher debounce when a package folder is installed, replaced, or removed under `Packages/`.

#### Scenario: Package installed while the service runs

- **WHEN** a package folder is installed, replaced, or removed under `Packages/`
- **THEN** the service reloads the remapping profiles within its watcher debounce

### Requirement: REQ-6 `ojd mod validate`

`ojd mod validate FOLDER` MUST check a package folder with `ModPackageStore.validate` and report the result as JSON with `--json`, exiting non-zero with the package's E4xxx code when the package is refused.

#### Scenario: Valid package

- **WHEN** the user runs `ojd mod validate FOLDER --json` on a valid package
- **THEN** the command prints the validation result as JSON and exits 0

#### Scenario: Refused package

- **WHEN** the package is refused
- **THEN** the command exits non-zero and names the package's E4xxx code

### Requirement: REQ-7 `ojd mod install`

`ojd mod install FOLDER` MUST install the package atomically into `Packages/<name>/`, refuse an existing name unless `--force` is given, never let `--force` override `requires` or an identity, profile id, or profile name clash, and change nothing with `--dry-run`.

#### Scenario: Install a new package

- **WHEN** the user runs `ojd mod install FOLDER` for a valid package with a new name
- **THEN** the package is installed atomically into `Packages/<name>/`

#### Scenario: Existing name

- **WHEN** a package with the same name is installed and `--force` is not given
- **THEN** the install is refused

#### Scenario: Force does not skip validation

- **WHEN** `--force` is given and the package fails `requires` or clashes on an identity, profile id, or profile name
- **THEN** the install is refused

#### Scenario: Dry run

- **WHEN** `--dry-run` is given
- **THEN** nothing on disk changes

### Requirement: REQ-8 `ojd mod list`

`ojd mod list` MUST list each installed package with its name, version, author, and the files it holds.

#### Scenario: List installed packages

- **WHEN** the user runs `ojd mod list`
- **THEN** each installed package is listed with its name, version, author, and files

### Requirement: REQ-9 `ojd mod remove`

`ojd mod remove NAME` MUST remove only `Packages/<NAME>/`, fail with an E4xxx code when no such package is installed, and change nothing with `--dry-run`.

#### Scenario: Remove an installed package

- **WHEN** the user runs `ojd mod remove NAME` for an installed package
- **THEN** only `Packages/<NAME>/` is removed

#### Scenario: Missing package

- **WHEN** no package named NAME is installed
- **THEN** the command fails with an E4xxx code

#### Scenario: Dry run

- **WHEN** `--dry-run` is given
- **THEN** nothing on disk changes

### Requirement: REQ-17 Out-of-range packages are skipped at runtime

When an installed package's `requires` does not admit the running version, the record, persona, and profile layers MUST skip all of its files, and `ojd mod list`, `ojd status`, and `ojd record list` MUST name the package with the E4002 reason.

#### Scenario: OJD update leaves a package's range

- **WHEN** the running version is outside an installed package's `requires`
- **THEN** none of its records, personas, or profiles are served
- **AND** `ojd mod list`, `ojd status`, and `ojd record list` name the package with the E4002 reason

### Requirement: REQ-10 Mod output envelopes

Each `ojd mod` command MUST print the `apiVersion`/`kind` envelope from `CLI+OutputKind.swift`, and `Resources/Schemas/v1beta1/cli-output.schema.json` MUST have one `$defs` entry per `ojd mod` command path.

#### Scenario: JSON output matches the schema

- **WHEN** any `ojd mod` command runs with `--json`
- **THEN** its output has the `apiVersion`/`kind` envelope and validates against that command's `$defs` entry
