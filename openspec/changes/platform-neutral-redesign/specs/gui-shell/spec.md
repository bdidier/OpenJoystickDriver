## ADDED Requirements

### Requirement: Coverage

Every CLI command SHALL have a place in the GUI. A repository test SHALL list the command tree and fail on a command without a mapped GUI location.

#### Scenario: New command

- **WHEN** a command is added without a GUI mapping
- **THEN** the coverage test fails

### Requirement: Main window structure

The main window SHALL use a split view with a sidebar. The toolbar SHALL hold a sidebar toggle and area buttons Status, Controllers, Profiles, Library, Access and Activity. The window title SHALL be the current area. `Command-1` to `Command-6` SHALL select the areas.

#### Scenario: Area switch

- **WHEN** the user presses `Command-3`
- **THEN** Profiles is selected and the title reads Profiles

### Requirement: Settings window

The Settings window SHALL use toolbar pane buttons (one selectable group, icon and label, not customizable) with panes General, Notifications, Command Line and Advanced, each with its own minimum size.

#### Scenario: Pane switch

- **WHEN** the user clicks Notifications
- **THEN** the pane changes and the window title reads Notifications

### Requirement: Floor and framework

The shell SHALL run on macOS 12 using AppKit containers with SwiftUI content. It SHALL NOT use APIs that need macOS 13 or later without an availability fallback.

#### Scenario: macOS 12 launch

- **WHEN** the app launches on the macOS 12 host
- **THEN** all six areas and the Settings window open

### Requirement: Confirmations and errors

Destructive actions SHALL ask through window-modal sheets whose text matches the action (an uninstall sheet SHALL NOT show repair text). Errors SHALL use one inline pattern: symbol, text, and a Details control that shows the `ojd explain` text.

#### Scenario: Uninstall

- **WHEN** the user chooses to uninstall
- **THEN** the sheet describes uninstall and names the Cancel button

### Requirement: No hard-coded user text

Every user-visible string SHALL come from the localization catalog, including sharing warnings. OS and transport detection SHALL use typed values, not display strings.

#### Scenario: Bluetooth detection

- **WHEN** the UI language is German
- **THEN** wireless-only actions still enable for Bluetooth controllers

### Requirement: Accessibility

All controls SHALL have accessibility labels from `a11y.*` keys, support Increase Contrast, Reduce Transparency, larger text and VoiceOver, and mirror in right-to-left locales.

#### Scenario: VoiceOver

- **WHEN** VoiceOver is on and the sidebar toggle is focused
- **THEN** it reads "Show Sidebar" or "Hide Sidebar" according to state

### Requirement: Visual approval

Each of the 13 screen groups (shell, Status, Controllers, Input Test, Profiles, Library, Access, Activity, Settings window, status item, destructive confirmations, errors, main menu) SHALL be shown to the user in light and dark appearance and approved before it counts as done.

#### Scenario: Unapproved group

- **WHEN** a group has no recorded user approval
- **THEN** its task stays unchecked
