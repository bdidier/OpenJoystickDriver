## ADDED Requirements

### Requirement: Coverage

Every CLI command SHALL have a place in the GUI. A repository test SHALL list the command tree and fail on a command without a mapped GUI location.

#### Scenario: New command

- **WHEN** a command is added without a GUI mapping
- **THEN** the coverage test fails

### Requirement: One obvious way

Each action SHALL appear once on a screen, and each fact SHALL appear once on a screen. A capability that a controller does not have, and a value that is unknown, SHALL be hidden: no row, box or card reads "Unknown", "Not needed" or "Unavailable". An area SHALL NOT repeat its own name as a heading or footnote. No screen SHALL ask the user to refresh to see connected controllers or live input.

#### Scenario: Action offered twice

- **WHEN** a screen would offer the same action in a second place
- **THEN** the second control is not shown

#### Scenario: Unknown battery

- **WHEN** a controller reports no battery level
- **THEN** the Controllers detail shows no battery, charging or cable row

### Requirement: Unknown values

A value field whose value is unknown, missing or not applicable SHALL show a single hyphen `-`, produced by one shared helper that every screen uses. No screen SHALL show a sentence, "Unknown", "None" or "N/A" in a value field in its place. A field that can never apply to the selected controller SHALL be hidden instead.

#### Scenario: No virtual HID profile published

- **WHEN** the selected controller has no published virtual HID profile
- **THEN** the Published as value reads `-`

#### Scenario: Unsupported capability

- **WHEN** the selected controller has no lighting
- **THEN** the detail shows no Lighting row or section

### Requirement: Native sections

Each section of a screen SHALL be a SwiftUI `Form` `Section` or a `List` section with default styling. On macOS 13 and later forms SHALL use the grouped form style; on macOS 12 they SHALL use the plain form style with the same sections and rows. Screens SHALL NOT use custom cards, tiles, tinted boxes or in-content area headings. An empty section SHALL show one line of secondary text.

#### Scenario: Empty section

- **WHEN** a section has no content
- **THEN** it shows one line of secondary text and keeps no reserved empty space

#### Scenario: macOS 12

- **WHEN** the app runs on macOS 12
- **THEN** each form shows the same sections and rows as on macOS 13, in the plain form style

### Requirement: Columns at every window size

Controllers, Profiles and Library SHALL show a list column and a detail column beside the sidebar. Each column SHALL have a minimum width, and the window's minimum size SHALL fit the sidebar and both columns. No area SHALL switch to a vertically stacked layout. The area's actions SHALL be toolbar items.

#### Scenario: Minimum window size

- **WHEN** the window is at its minimum size on Controllers
- **THEN** the sidebar, the controller list and the detail are side by side, and no text in the list or the detail's labels is cut off

### Requirement: Main window navigation

The main window SHALL switch areas from a full-height sidebar that lists five areas in this order, each with a symbol: Controllers, Profiles, Library, Access and Activity. `Command-1` to `Command-5` SHALL select the areas in that order. The sidebar SHALL be shown by default; a toolbar button and View > Hide Sidebar hide it. Controllers and Profiles SHALL show a list column between the sidebar and the detail; Library, Access and Activity SHALL be one pane.

#### Scenario: Area switch

- **WHEN** the user presses `Command-2`
- **THEN** Profiles is selected and the title reads Profiles

#### Scenario: Window opens

- **WHEN** the main window opens
- **THEN** the sidebar lists the five areas and the toolbar holds the sidebar toggle, the area title and subtitle, and no area switcher

#### Scenario: Sidebar hidden

- **WHEN** the user chooses View > Hide Sidebar
- **THEN** the sidebar hides, `Command-1` to `Command-5` still select areas, and the menu item reads Show Sidebar

### Requirement: Main window toolbar

The toolbar SHALL show the selected area's title and a subtitle that summarizes it, and SHALL hold only that area's actions. The toolbar SHALL NOT switch areas. The content SHALL NOT repeat the area title.

#### Scenario: Controllers selected

- **WHEN** Controllers is selected with one controller connected
- **THEN** the toolbar reads Controllers with the subtitle 1 controller connected, and the content has no Controllers heading

### Requirement: Problem banner

The main window SHALL show one banner at its top only while the driver or the service has a problem. The banner SHALL state the problem in one line and offer Details, which shows the `ojd explain` text. The banner SHALL disappear when the problem clears. The banner SHALL NOT show controller counts.

#### Scenario: Healthy app

- **WHEN** the driver and the service are healthy
- **THEN** no banner is shown

#### Scenario: Driver installed and active

- **WHEN** the driver extension is installed and activated
- **THEN** the banner does not report the driver as missing

### Requirement: Controllers area

The Controllers area SHALL detect controllers automatically and SHALL show the count of connected controllers. It SHALL have no Refresh control. With no controller connected, it SHALL show one line of empty-state text and no button. The controller detail SHALL show the virtual HID profile once, in its Published as row. Endpoints SHALL appear under Advanced. Ownership SHALL appear as one row with one action.

#### Scenario: Controller attaches

- **WHEN** a controller is attached
- **THEN** it appears in the list without any user action

#### Scenario: Empty state

- **WHEN** no controller is connected
- **THEN** the area shows one line of text and no button

### Requirement: Input Test

Input Test SHALL be the Test section of the selected controller's detail in the Controllers area. It SHALL NOT open a separate window and SHALL NOT have an Open Input Test control. The Test section SHALL name the physical controller. Stick and trigger readouts SHALL be the only display of analog values. Motion calibration SHALL appear only for a controller with a gyroscope. Lighting SHALL appear only for a controller that supports it. Each D-pad direction SHALL have its own symbol.

#### Scenario: Test Input from the status item

- **WHEN** the user chooses Test Input for a controller in the status item
- **THEN** the Controllers area opens that controller's Test section

#### Scenario: Controller without gyroscope

- **WHEN** the selected controller has no gyroscope
- **THEN** the Test section shows no Motion calibration

#### Scenario: Physical name

- **WHEN** the GameSir G7 SE is selected
- **THEN** the Test section names the GameSir G7 SE, not the virtual device

### Requirement: Profiles area and profile creation

The Profiles area SHALL have one control that creates a profile. The creation sheet SHALL choose from connected controllers and SHALL NOT ask for vendor or product IDs. The default profile name SHALL come from the chosen controller. The sheet SHALL show no validation message until a field is edited or Create is pressed.

#### Scenario: Controller chosen

- **WHEN** the user opens the creation sheet with a controller connected
- **THEN** the sheet lists that controller and proposes its name as the profile name

#### Scenario: No controller connected

- **WHEN** the user opens the creation sheet with no controller connected
- **THEN** the sheet lists no controller and Create is disabled

### Requirement: Library area

The Library area SHALL have one Validate action, in the toolbar, and one empty line per section. The number of built-in records SHALL appear as a labelled count, not as a sentence.

#### Scenario: Built-in records

- **WHEN** the Library lists the built-in controller records
- **THEN** the count appears as a labelled number

### Requirement: Access area

The Access area SHALL show each access grant as one row with its status. A grant that the app does not need SHALL NOT appear. The full socket path SHALL NOT appear.

#### Scenario: Grant not needed

- **WHEN** the app does not need keyboard and pointer access
- **THEN** no keyboard and pointer row appears

### Requirement: Settings window

The Settings window SHALL use toolbar pane buttons (one selectable group, icon and label, not customizable) with panes General, Notifications, Command Line and Advanced, each with its own minimum size.

#### Scenario: Pane switch

- **WHEN** the user clicks Notifications
- **THEN** the pane changes and the window title reads Notifications

### Requirement: Floor and framework

The shell SHALL run on macOS 12 using AppKit containers with SwiftUI content. It SHALL NOT use APIs that need macOS 13 or later without an availability fallback.

#### Scenario: macOS 12 launch

- **WHEN** the app launches on the macOS 12 host
- **THEN** all five areas and the Settings window open

### Requirement: Confirmations and errors

Destructive actions SHALL ask through window-modal sheets whose text matches the action (an uninstall sheet SHALL NOT show repair text). Errors SHALL use one inline pattern: symbol, text, and a Details control that shows the `ojd explain` text. The problem banner SHALL use the same pattern.

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

- **WHEN** VoiceOver is on and the Controllers segment is focused
- **THEN** it reads the area name and whether the area is selected

### Requirement: Visual approval

Each of the 13 screen groups (shell, problem banner, Controllers, Input Test, Profiles, Library, Access, Activity, Settings window, status item, main menu, destructive confirmations, errors) SHALL be shown in light and dark appearance and approved before it counts as done.

#### Scenario: Unapproved group

- **WHEN** a group has no recorded user approval
- **THEN** its task stays unchecked
