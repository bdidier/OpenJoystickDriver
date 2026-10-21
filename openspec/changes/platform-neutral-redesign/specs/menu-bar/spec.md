## ADDED Requirements

### Requirement: Menu bar is a subset of the GUI

Every status-item and main-menu action SHALL exist in the main window or Settings window.

#### Scenario: Menu action

- **WHEN** the user chooses Disconnect Wireless Link from the status item
- **THEN** the same action is available on the controller's detail page

### Requirement: Fixed status-item layout

The status item SHALL show, in order: status line; Controllers submenu; Profiles submenu (Activate, Deactivate); Grant Access; Open Window; Settings; Help submenu (Activity Log, Explain Error Code, Report a Problem, Project Website); Quit. The Controllers submenu SHALL hold one submenu per connected controller, named for it, and each SHALL hold Suspend/Resume, Test Input, Active Profile, Disconnect Wireless Link and Show in Window, acting on that controller. Active Profile SHALL list only the profiles that apply to that controller (its model, and its unit when the profile names one) and check the one active for it; choosing a profile activates it through the service, which scopes it by the profile's own device. With no controller connected, the Controllers submenu SHALL hold one disabled row that says no controller is connected. Items SHALL be disabled when not applicable and SHALL NOT be hidden, except Grant Access, which SHALL be hidden while every permission is granted.

#### Scenario: No wireless controller

- **WHEN** a controller is connected over a wired link
- **THEN** its Disconnect Wireless Link item is visible and disabled

#### Scenario: Every permission granted

- **WHEN** every permission is granted
- **THEN** Grant Access is not in the menu

#### Scenario: Permission missing

- **WHEN** a permission is missing
- **THEN** Grant Access is visible and enabled

#### Scenario: Two controllers

- **WHEN** two controllers are connected
- **THEN** the Controllers submenu lists both, each with its own five actions, and choosing Suspend under one acts only on that controller

#### Scenario: No controller

- **WHEN** no controller is connected
- **THEN** the Controllers submenu holds one disabled row that says no controller is connected

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

The main menu SHALL have App, File, Edit, View, Controller, Profile, Window and Help menus. File SHALL hold Import/Export Profile, Install Record or Mod, Save Support Report and Save Activity Log. View SHALL hold the five areas (Controllers, Profiles, Library, Access and Activity) with `Command-1` to `Command-5`, and Full Screen. Every item SHALL have an action, except the first row of the Controller menu: one disabled informational row that names the controller the Controller and Profile menus act on (the controller selected in the Controllers area), or says that no controller is connected or none is selected. The Controller and Profile items that act on a controller SHALL be disabled without such a controller.

#### Scenario: Controller menu target

- **WHEN** two controllers are connected and one is selected in the Controllers area
- **THEN** the Controller menu's first row shows that controller's name and Suspend, Test Input, Disconnect Wireless Link and Deactivate Profile act on it

#### Scenario: No controller selected

- **WHEN** controllers are connected but none is selected, or the selected one has disconnected
- **THEN** the first row says no controller is selected and the controller items are disabled

#### Scenario: Save support report

- **WHEN** the user chooses File > Save Support Report
- **THEN** a save panel opens and the report writes on confirm
