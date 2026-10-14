# mod-sdk Specification

## Purpose

A sample mod package and the documentation that teach users to write and install packages.

## Requirements

### Requirement: REQ-13 Sample package

`docs/sdk/sample/` MUST hold a package that `ojd mod validate` accepts, with at least one record, one profile, and one persona, and `swift test` MUST validate it and run `ojd record test` on its record.

#### Scenario: Validate the sample

- **WHEN** `swift test` runs `ojd mod validate docs/sdk/sample --json`
- **THEN** the package is accepted
- **AND** `ojd record test` passes on its record

### Requirement: REQ-14 Mod documentation

`wiki/Writing-Controller-Mods.md` MUST state first that the USB extension's product list is Apple-signed and cannot be extended, and `wiki/Command-Line.md`, `wiki/Command-Reference.md`, `wiki/Controller-Records.md`, and `wiki/_Sidebar.md` MUST describe what ships.

#### Scenario: Reader opens the mod page

- **WHEN** a reader opens `wiki/Writing-Controller-Mods.md`
- **THEN** its first statement says the USB extension's product list is Apple-signed and cannot be extended
