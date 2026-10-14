# mod-localization Specification

## Purpose

The app and the CLI explain mod package errors in the user's language, and every mod string is reviewed in each catalog.

## Requirements

### Requirement: REQ-11 E3029 explained in the user's language

The app and the CLI MUST show the localized `error.E3029` explanation for a refused package profile change, not `error.generic` or the service's English message.

#### Scenario: Refused package profile change

- **WHEN** the service refuses a package profile change with E3029
- **THEN** the app and the CLI show the localized `error.E3029` text and keep the code E3029

### Requirement: REQ-12 Reviewed mod strings

The strings of E4001-E4007, E3029, `cli.explain.area.mod`, and each new `ojd mod` string MUST be reviewed in every catalog under the rules of `LOCALIZATION.md`, and `python3 Scripts/Quality/check_localization_keys.py` MUST pass.

#### Scenario: Catalog check

- **WHEN** `python3 Scripts/Quality/check_localization_keys.py` runs after the review
- **THEN** it exits 0
