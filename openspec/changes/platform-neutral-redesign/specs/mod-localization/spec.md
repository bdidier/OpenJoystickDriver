## MODIFIED Requirements

### Requirement: REQ-11 E3029 explained in the user's language

The app and the CLI MUST show the localized `error.E3029.message` text for a refused package profile change, not `error.generic` or the service's English message.

#### Scenario: Refused package profile change

- **WHEN** the service refuses a package profile change with E3029
- **THEN** the app and the CLI show the localized `error.E3029.message` text and keep the code E3029

### Requirement: REQ-12 Reviewed mod strings

The strings of E4001-E4007 (`error.E4001.message` to `error.E4007.message`), E3029, `cli.explain.group.areaMod`, and each `ojd mod` string (`cli.mod.group.*` and `cli.mod.<command>.*`) MUST be reviewed in every catalog under the rules of `LOCALIZATION.md`.
Every key MUST have a translator comment, a value with more than one format specifier MUST number each one, and `python3 Scripts/Quality/check_localization_keys.py` MUST pass.

#### Scenario: Catalog check

- **WHEN** `python3 Scripts/Quality/check_localization_keys.py` runs after the review
- **THEN** it exits 0
