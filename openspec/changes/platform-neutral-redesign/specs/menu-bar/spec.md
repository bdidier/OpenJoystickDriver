## ADDED Requirements

### Requirement: Menu bar is a subset of the GUI

Every status-item and main-menu action SHALL exist in the main window or Settings window.

#### Scenario: Menu action

- **WHEN** the user chooses Disconnect Wireless Link from the status item
- **THEN** the same action is available on the controller's detail page

### Requirement: Fixed status-item layout

The status item SHALL show, in order: status line; Controllers submenu (Suspend/Resume, Test Input, Active Profile, Disconnect Wireless Link, Show in Window); Profiles submenu (Activate, Deactivate); Grant Access; Open Window; Settings; Help submenu (Activity Log, Explain Error Code, Report a Problem, Project Website); Quit. Items SHALL be disabled when not applicable and SHALL NOT be hidden.

#### Scenario: No wireless controller

- **WHEN** no controller is connected over a wireless link
- **THEN** Disconnect Wireless Link is visible and disabled

### Requirement: Template icon and push updates

The status item icon SHALL be a template image. State SHALL update from service notifications; polling MAY serve only as a fallback.

#### Scenario: Controller attaches

- **WHEN** a controller attaches
- **THEN** the status line updates within one second without a poll interval

### Requirement: Localized status line

The status line SHALL be built from one localized format string with positional arguments, not by joining fragments.

#### Scenario: Arabic

- **WHEN** the language is `ar-SA`
- **THEN** the status line reads right to left as one phrase

### Requirement: Main menu set

The main menu SHALL have App, File, Edit, View, Controller, Profile, Window and Help menus. File SHALL hold Import/Export Profile, Install Record or Mod, Save Support Report and Save Activity Log. View SHALL hold the six areas with `Command-1` to `Command-6`, Show/Hide Sidebar (`Control-Command-S`) and Full Screen. Every item SHALL have an action.

#### Scenario: Save support report

- **WHEN** the user chooses File > Save Support Report
- **THEN** a save panel opens and the report writes on confirm
