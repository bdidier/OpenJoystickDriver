## Purpose

What a release must hold before it is tagged: a dated CHANGELOG section and a passing check list.

## ADDED Requirements

### Requirement: REQ-15 Release CHANGELOG section

`CHANGELOG.md` MUST list the mod package feature, E3029, and E4001-E4007 on one line each, and its `[Unreleased]` section MUST become `[0.6.0-alpha.1]` with the release date.

#### Scenario: Release commit

- **WHEN** the release commit is approved
- **THEN** `CHANGELOG.md` has `## [0.6.0-alpha.1] - <date>` with one line each for mod packages, E3029, and E4001-E4007

### Requirement: REQ-16 Full check list

Every command in the Checks list of `CLAUDE.md`, and `./Scripts/ojd test parsers-macos14`, MUST exit 0 on the final tree.

#### Scenario: Final tree

- **WHEN** each command of the `CLAUDE.md` Checks list and `./Scripts/ojd test parsers-macos14` runs on the final tree
- **THEN** each exits 0
