## ADDED Requirements

### Requirement: Package files carry a header

`mod.json` and every file that it lists MUST carry `apiVersion` and `kind`: `mod.json` has `apiVersion: openjoystickdriver/v1alpha1` and `kind: ModPackage`, and a listed file has the `kind` of its document (`Controller`, `ControllerPatch`, `Profile` or `VirtualDevice`).
A file with a missing or unsupported `apiVersion` MUST be refused with E5001, and any other invalid listed file with E4003.

#### Scenario: Unsupported apiVersion

- **WHEN** `ojd mod validate FOLDER` reads a package whose `mod.json` or a listed file has an unsupported `apiVersion`
- **THEN** the command exits non-zero and names E5001

## MODIFIED Requirements

### Requirement: REQ-4 Snapshot lists package profiles

`ApplicationServiceRemappingSnapshotPayload` MUST carry `packageProfiles`, a list of `{profileID, package}`.
A payload without the key MUST fail to decode.

#### Scenario: Snapshot with a package profile

- **WHEN** a package profile is served
- **THEN** the remapping snapshot lists `{profileID, package}` for it

#### Scenario: Older payload without the key

- **WHEN** a snapshot payload without `packageProfiles` is decoded
- **THEN** decoding fails

### Requirement: REQ-6 `ojd mod validate`

`ojd mod validate FOLDER` MUST check a package folder with `ModPackageStore.validate` and report the result as JSON with `--json`, exiting non-zero with the package's E4xxx code, or E5001 for an unsupported `apiVersion`, when the package is refused.

#### Scenario: Valid package

- **WHEN** the user runs `ojd mod validate FOLDER --json` on a valid package
- **THEN** the command prints the validation result as JSON and exits 0

#### Scenario: Refused package

- **WHEN** the package is refused
- **THEN** the command exits non-zero and names the package's E4xxx code, or E5001 for an unsupported `apiVersion`

### Requirement: REQ-10 Mod output envelopes

Each `ojd mod` command MUST print the `apiVersion`/`kind` envelope with `apiVersion: openjoystickdriver/v1alpha1`, and `Resources/Schemas/cli-output.schema.json` MUST have one `$defs` entry per `ojd mod` command path.

#### Scenario: JSON output matches the schema

- **WHEN** any `ojd mod` command runs with `--json`
- **THEN** its output has the `apiVersion`/`kind` envelope and validates against that command's `$defs` entry
