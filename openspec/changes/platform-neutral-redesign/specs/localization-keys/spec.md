## ADDED Requirements

### Requirement: Namespaces

Localization keys SHALL begin with one of `term.`, `action.`, `status.`, `ui.<area>.`, `ui.menu.`, `ui.extra.`, `ui.settings.<pane>.`, `a11y.`, `cli.<group>.<command>.`, `error.<code>.`, `notify.`, `platform.<os>.`. Segments SHALL be lowerCamelCase except error codes. OS-specific words SHALL appear only under `platform.`.

#### Scenario: Key shape

- **WHEN** the checker reads a key outside the namespaces
- **THEN** it fails

#### Scenario: OS word

- **WHEN** a non-`platform` value contains "DriverKit"
- **THEN** the checker fails

### Requirement: Format specifiers and plurals

Every string with more than one argument SHALL use positional specifiers (`%1$@`). Every key that takes a count SHALL have a `.stringsdict` entry with the plural categories each locale needs.

#### Scenario: Missing position

- **WHEN** a value has `%@ %@`
- **THEN** the checker fails

### Requirement: Translator comments

Every key in the `en-US` source SHALL have a translator comment.

#### Scenario: No comment

- **WHEN** a key lacks a comment
- **THEN** the checker fails

### Requirement: Formats kept

The catalog SHALL stay `.strings` and `.stringsdict` in 22 bundles (`C`, `en-US` and 20 locales). Resolution SHALL stay by macOS preferred languages with fallback to `en-US`. Call sites SHALL pass a key only.

#### Scenario: Missing key

- **WHEN** a literal key is absent from `en-US`
- **THEN** `check_localization_keys.py` fails

### Requirement: Crowdin

The repository SHALL contain `crowdin.yml` with source `en-US.lproj/*.strings` and `*.stringsdict` and translation path `%osx_locale%.lproj/%original_file_name%`. The build SHALL NOT copy `Localizable.template.*` into bundles.

#### Scenario: Config

- **WHEN** a check parses `crowdin.yml`
- **THEN** both file patterns and the translation path are present

### Requirement: Re-key is mechanical first

Re-keying SHALL change keys without changing meaning in any locale. Translation review decisions SHALL be separate tasks.

#### Scenario: Value comparison

- **WHEN** a check maps old keys to new keys
- **THEN** every locale value is identical before and after, except merged duplicates and positional specifiers
