## MODIFIED Requirements

### Requirement: REQ-15 Release CHANGELOG section

`CHANGELOG.md` MUST list the mod package feature, E3029, and E4001-E4007 on one line each in its `[Unreleased]` section, and MUST list every **BREAKING** item of the `platform-neutral-redesign` change: the rejected document shapes, the default `Generic` persona and the removed CLI words.
The release commit MUST rename that section `[0.6.0-alpha.1]` with the release date.

#### Scenario: Release commit

- **WHEN** the release commit is made
- **THEN** `CHANGELOG.md` has `## [0.6.0-alpha.1] - <date>` with one line each for mod packages, E3029, and E4001-E4007, and a **BREAKING** line for each breaking item

#### Scenario: Before the release commit

- **WHEN** the release commit is not yet made
- **THEN** those lines are in `## [Unreleased]`

### Requirement: REQ-16 Full check list

Every command in the `check` recipe of the `justfile`, which includes `./Scripts/ojd test parsers-macos14`, the `crowdin.yml` parse test and the schema constant-equality test, MUST exit 0 on the final tree.

#### Scenario: Final tree

- **WHEN** `just check` runs on the final tree
- **THEN** each command exits 0
