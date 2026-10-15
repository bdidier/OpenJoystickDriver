## Context

See `proposal.md` for the reason. This change is planning only: it holds specs and tasks, no code.
Evidence comes from six read-only audits of `feat/0.6.0-alpha.1` (CLI coverage, architecture, issues and resources, GUI and localization, schemas, localization review) and from a live run on 2026-10-14 (macOS 27, arm64, app 0.5.0-beta.5, SDL 3.4.18 through `Tools/SDLGamepadProbe`).
File and line references below are from that branch and move as work lands.

Floor: macOS 12. Test hosts: this Mac (macOS 27) and an Intel MacBook Pro A1398 on macOS 12. There is no macOS simulator, and a macOS VM has no Bluetooth or USB-HID passthrough.

### User decisions (authoritative, 2026-10-14)

| # | Decision (user's words in quotes) |
| --- | --- |
| 1 | "`1209:4A4F` is for Generic HID, and `045E:02FD` is for SDL-based solutions." |
| 2 | "the version token was taken from Kubernetes, so they are a big inspiration for schema versioning." "no domain sadly, unless you want to host it on github here--biome.js-style?" |
| 3 | "should use idiomatic, self-descriptive names for any construct, parameter, and code-related item. No aliases retaining. It is a breaking change." |
| 4 | `U-` and `E-` prefixes: "if you need to." |
| 5 | Clones that reuse an ID: "if you need to. you never know if it's a hit-or-miss unless somebody with a clone tests it out. user has the other clone mentioned in wiki." |
| 6 | Keep `.strings` and `.stringsdict`; "yes, agreed!" to the namespaces `term.*`, `action.*`, `status.*`, `ui.<area>.*`, `ui.menu.*`, `ui.extra.*`, `ui.settings.<pane>.*`, `a11y.*`, `cli.<group>.<command>.*`, `error.<code>.*`, `notify.*`, `platform.<os>.*`; plus `crowdin.yml`. |
| 7 | "we'll just redo the GUI entirely. it's a mess." The toolbar pane buttons of commit `6858be2e` "were awesome!" "CLI <= menubar => GUI". |
| 8 | Control vocabulary: "AGREED!" |
| 9 | "our CLI uses <https://clig.dev/> guidelines + Apple." |
| 10 | "OJD should not be hard-coding/make workarounds that are baked in... users don't have to start modifying source code." |
| 11 | The seven Microsoft IDs in the DEXT are Apple's `transport.usb` grant (`docs/development/signing.md:36`). |
| 12 | DS3 Bluetooth pairing: macOS 27 asks a PIN the DS3 lacks; older macOS pairs. Test host is the A1398 on macOS 12. |
| 13 | Hardware available: Razer Wolverine V1 TE (GIP), GameSir G7 SE (GIP, 3537:1010), genuine Sony CECHZC2E DS3, a DS3 clone, genuine Sony DS4 v2, on two USB hubs; SDL3 apps such as Steam. The caller also lists an 8BitDo `2DC8:301B`. |
| 14 | One massive breaking release `0.6.0-alpha.1`; no legacy; streaming (WebRTC etc.), SDK/API, user configs, SDL/Wine/CrossOver/browser support in scope. |

## Goals / Non-Goals

Goals:

- A new controller or clone can be supported by adding a JSON document, without a Swift change, when its protocol is one of the algorithmic ones or is fully expressible as data.
- One name per concept in code, documents, CLI, GUI and localization.
- SDL, Wine/CrossOver and browsers see a usable gamepad from the default persona.

Non-Goals:

- No runtime upgrader, `ojd migrate`, alias, fallback decoder or compatibility shim (decisions 2, 3).
- No DriverKit extension for a second virtual backend; `IOHIDUserDevice` stays the only virtual backend (carried over from `release-0-6-0-alpha-1`).
- No parser for controllers that need a new algorithmic protocol; those stay code (GIP authentication, Switch subcommands, Sony CRC, Steam, descriptor interpreters).
- No copying of GPL or other-licensed sources; protocol facts only.

## Decisions

### D1 Target architecture

Layers, each with one owner type. A device is observed, linked, bound to a record mode, driven by a protocol, reduced to canonical state, mapped by the user's profile, and served by one route.

| Layer | Content | Today's problem |
| --- | --- | --- |
| L0 Observation | Raw OS facts: IOHID properties, USB descriptors, BLE advertisement | Observed facts are mixed with identity |
| L1 Link | `kind` (`usb`, `bluetoothClassic`, `bluetoothLE`, `radioReceiver`), `access` (`ioHid`, `ioUsbHost`, `usbDriverKit`, `coreBluetoothGatt`), address | Switch 2 invents locations `0xB1E0_0000` |
| L2 Binding | Model record, `modes[]` chosen by link kind and interface signature, and extra match keys; roles | `DeviceIdentifier` carries VID:PID and location |
| L3 Protocol | A protocol description (data) plus driver code with typed parameters | 25 `ControllerQuirk` tags in `Sources/OpenJoystickDriverKit/Protocol/Catalog/TransportProfiles.swift:99-183` |
| L4 Canonical state | Controls from the vocabulary, motion, touch, battery | Two vocabularies (`ControlID`, `RemappingButton`) |
| L5 Mapping | User profile over canonical state | none |
| L6 Serving | One `ServingRoute` per controller from a pure policy | Decided in several places |

Record flow: observed device, then link, then record `modes[]` with match keys (interface signature, manufacturer and product strings, read-only behavioral probes for same-ID clones), then a protocol description, then canonical state, then user mapping, then one serving-route policy, then a persona. Personas are `Generic` `1209:4A4F` (default) and `SdlCompatible` `045E:02FD`, with an OJD-published SDL mapping.

### D2 Record and schema model

A `Controller` record (see `specs/controller-records`) declares:

- `model` (`id`, `name`, `manufacturer`) and `modes[]`. Each mode has `match` keys, `protocol` (an id plus typed `parameters`), `interface` selection (for example the HID interface range 2 to 5 of the Steam Deck as data), and optional `session` steps.
- Declarative input layouts: bit offset and size, signed fields, 10 to 16 bit values, 16-bit triggers, inversion, more than four axes, extra buttons, report ids, trigger rest value -1, hat sources.
- Vendor control transfers (`bmRequestType`, `bRequest`, `wValue`, `wIndex`, `wLength`), init, keepalive and settle sequences, acknowledgement rules. These come from issues #38 (ShanWan), #22, #21, #35.
- Output templates: fixed bytes, scale, motor positions, resend interval (the xpad and `hid.report-layout` rumble cases).
- Multi-identity linking: one model reachable through several VID:PID pairs and several link kinds (wired, dongle, Bluetooth, and a mode switch changing the PID, as the 8BitDo family does).

Declared full, not as deltas. The record carries facts only (no provenance, per `Resources/Schemas/AGENTS.md`).

What stays in code, because it is an algorithm and not a table: GIP authentication, Switch subcommands, Sony CRC, Steam protocol, the `hid.descriptor` and `hid.report-layout` interpreters, the USB claim and transfer machinery.

Quirk to typed-parameter conversions (examples; the full table is task 5):

| Old `ControllerQuirk` | New |
| --- | --- |
| `switch-2` | protocol `nintendo.switch2`, parameter `layout`: `pro`, `joyConLeft`, `joyConRight`, `gameCube` |
| input-only | protocol `nintendo.switch-input-only` |
| triton, neptune | protocols `valve.steam-triton`, `valve.steam-deck`; interface range is data |
| GameSir `g7ProUSB` | wire-dialect parameter |
| `shield-2015` | `reportRevision` parameter |
| wireless-adapter, strikepad | role and motion-scale parameters |
| `wr007`, `scuf-envision`, `z-rz-brake-left`, `dragonrise` | `input.hidUsageMap` data |
| share-offset | `shareButton: { fromEnd: N }` |
| dpad-pressure | `hatSource` |

Family defaults that live in Swift today (`MacOSOwnedOutput.swift:38-62`, `DeviceCatalog.swift:100-140`, `ProtocolClassifier.swift:316-349`, `ControllerProfileCapabilities.swift:10-16`, `ControllerTuning+Layers.swift:72-85`) move to `Resources/Protocols/<family>.json`. Python tables (`SDL_IDENTITY_FAMILIES`, `SDL_EXCLUSIONS`, `STEAM_VARIANTS`, `SWITCH_2_IDENTITIES`, `DRIVER_HANDLED_DEVICE_FLAGS` in `Scripts/Catalog/generate_controller_catalog.py` and `generate_xpad_records.py`) become authored data. Remaining VID:PID literals to remove: `USB/Configuration.swift:9-12,18-27`, `VirtualDeviceProfile.swift:36-61`, `Switch2BluetoothLEHub.swift:15-41,49-50`, `PassiveUSBDescriptorProbe.swift:6-8`, `RecordReport.swift:87`.

An equivalence harness builds the driver for every bundled record before and after the change and compares driver type and configuration. It gates the generator and quirk work.

Counts to preserve (families): xbox.gip 210, xbox.xusb 208, vendor.ps3-third-party 75, sony.dualshock4 62, xbox.xid 59, nintendo.switch1 32, vendor.gamesir 26, hid.descriptor 21, sony.dualsense 21, valve.steam-controller 12, nvidia-shield 4, hid.report-layout 4, flydigi 2, sixaxis 2; 696 generated records plus 54 overrides.

### D3 Control vocabulary and crosswalk

One position-based set. A label never renames an id. Values are UpperCamelCase (decision 2); the schema `$defs/control` is the only definition, and one Swift enum mirrors it.

| OJD id | W3C index | SDL3 | Linux evdev | HID page:usage | Apple GameController |
| --- | --- | --- | --- | --- | --- |
| `South`, `East`, `West`, `North` | 0, 1, 2, 3 | SOUTH (`a`), EAST (`b`), WEST (`x`), NORTH (`y`) | BTN_SOUTH, BTN_EAST, BTN_WEST, BTN_NORTH | Button:1 to 4 | ButtonA, ButtonB, ButtonX, ButtonY |
| `LeftShoulder`, `RightShoulder` | 4, 5 | LEFT_SHOULDER, RIGHT_SHOULDER | BTN_TL, BTN_TR | Button:n | LeftShoulder, RightShoulder |
| `LeftTrigger`, `RightTrigger` (axis 0 to 1) | 6, 7 | LEFT_TRIGGER, RIGHT_TRIGGER | ABS_Z, ABS_RZ | GenericDesktop Z, Rz or Simulation Accelerator, Brake | LeftTrigger, RightTrigger |
| `Back` | 8 | BACK | BTN_SELECT | Button:n | ButtonOptions |
| `Start` | 9 | START | BTN_START | GenericDesktop Start (0x3D) | ButtonMenu |
| `LeftStickClick`, `RightStickClick` | 10, 11 | LEFT_STICK, RIGHT_STICK | BTN_THUMBL, BTN_THUMBR | Button:n | LeftThumbstickButton, RightThumbstickButton |
| `DpadUp`, `DpadDown`, `DpadLeft`, `DpadRight` | 12 to 15 | DPAD_* | BTN_DPAD_* or ABS_HAT0 | GenericDesktop Hat switch | DirectionPad |
| `Guide` | 16 | GUIDE | BTN_MODE | GenericDesktop System Main Menu | ButtonHome |
| `Capture` | none | MISC1 | KEY_RECORD | Consumer page | ButtonShare |
| `Microphone` | none | MISC1 (PS5) | none | Telephony or Consumer mute | none |
| `TouchpadClick` | none | TOUCHPAD | BTN_TOUCH (touch device) | Button:n | TouchpadButton |
| `LeftPaddle1`, `LeftPaddle2`, `RightPaddle1`, `RightPaddle2` | none | LEFT/RIGHT_PADDLE1/2 | BTN_GRIPL, BTN_GRIPL2, BTN_GRIPR, BTN_GRIPR2 | Button:n | XboxPaddleOne to Four |
| `Auxiliary1` to `Auxiliary8` | none | MISC2 to MISC6 | BTN_TRIGGER_HAPPY1+ | Button:n | none |
| `LeftStickX`, `LeftStickY`, `RightStickX`, `RightStickY` | axes 0 to 3 | LEFTX, LEFTY, RIGHTX, RIGHTY | ABS_X, ABS_Y, ABS_RX, ABS_RY | GenericDesktop X, Y, Rx, Ry | LeftThumbstick, RightThumbstick |

Rules: `Share` and `Options` are not ids. PS4 Share and Xbox View are `Back`; PS Options, Xbox Menu and Switch Plus are `Start`; Xbox Share and Switch Capture are `Capture`. Y axes are positive down (W3C, SDL, Linux agree). Labels and glyphs come from a per-model `labels` map. Exact HID usage ids are confirmed against the HID Usage Tables at implementation (the audit did not fetch them). Rumble actuators: `LowFrequency`, `HighFrequency`, `LeftTrigger`, `RightTrigger`, `LeftHaptic`, `RightHaptic`. Keyboard keys use W3C UI Events `KeyboardEvent.code` values.

### D4 Schema set and versioning

Kinds: `Controller`, `ControllerPatch` (RFC 7396 JSON Merge Patch), `Profile`, `VirtualDevice`, `ModPackage`, `ErrorCatalog`, `AccessGrants`, `SupportDiagnostic` (CloudEvents envelope), plus the CLI output and endpoint message kinds, and a `Settings` kind for the new settings file. Shared definitions live in `vocabulary.schema.json`. The old `controller-override` `add` becomes a plain `Controller`; `defaults` becomes a `ControllerPatch` with `selector.all`; `persona` becomes `VirtualDevice`.

Assumed (veto-able) and recorded here:

| Assumption | Reason |
| --- | --- |
| `apiVersion: openjoystickdriver/v1alpha1` (Kubernetes `group/version` grammar, group is the project name) | No domain is owned. Kubernetes alpha means "may break without notice", which matches `0.6.0-alpha.1`. Promote to `v1beta1` when frozen. |
| `$id: https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha1/<kind>.schema.json`, published from flat sources `Resources/Schemas/<kind>.schema.json`, version written in each file, no version folder | Decision 2 (biome.js style). The task prepares the Pages publish; the user turns Pages on. |
| Fields lowerCamelCase, enum values UpperCamelCase, CLI argument values lowercase kebab-case mapped 1:1 (for example `ojd virtual set generic`) | Kubernetes API conventions plus clig.dev. |
| Raw bytes are uppercase hex pairs with single spaces, pattern `^[0-9A-F]{2}( [0-9A-F]{2})*$` | Kubernetes uses base64; these bytes are read against USB traces. |
| An unknown or missing `apiVersion` is rejected with a new error code | No runtime upgrade (decision 2). |
| Stored files are not migrated; `U-` and `E-` prefixes may change | Decision 4. |

The 0.5.0-beta.4 audit shows `v1beta1` never shipped, so rewriting the layout breaks only unreleased files. Instances drop `$schema`. A test asserts the Swift constant equals the Python constant equals every schema's `apiVersion` const. `Scripts/Quality/validate_schemas.py` extends to `docs/sdk/sample/**`, profile fixtures and access-grant fixtures.

### D5 Serving routes and personas

`ServingRoute` is `NativePassThrough(allowance)`, `VirtualHid(persona)`, `ExtensionOwned`, or `OutputDisabled`, decided once by a pure `ServingPolicy` from record, link, user setting and per-app allowance. The current automatic profile default (`VirtualHIDProfileSelector.swift:50`, spoof `045E:02FD`) becomes `Generic`.

Assumed (veto-able): default persona is `Generic` everywhere; `SdlCompatible` is opt-in per model or per app. Reason: SDL 3.4.18 does not list the `045E:02FD` persona with default hints, nor with `SDL_JOYSTICK_HIDAPI_XBOX(_ONE)=1`, `SDL_JOYSTICK_MFI=1` or `--gc-prewarm`; it appears only with `SDL_JOYSTICK_HIDAPI=0` (through MFi, as `045E:02E0`). The reading is that SDL's HIDAPI Xbox driver claims the device and then fails to open it, which matches the wiki's Steam and SDL failure reports. The `1209:4A4F` persona enumerates and, with the mapping line below, SDL reports `is_gamepad=yes` with axes at 0 at rest. Button and axis directions are not yet confirmed by presses.

The `SdlCompatible` persona needs a hardware-evidenced fix so SDL's HIDAPI Xbox driver opens it. Until the fix lands it is documented as not working with default SDL hints. No Microsoft ID appears outside this persona: `1209:0001` (SDK sample), `4F4A:4449` (retired) and the 045E values in the HIDTool subcommands are reconciled (sample uses a documented sample ID; retired ID removed; HIDTool takes IDs from records).

### D6 SDL, Wine/CrossOver and browsers

| Consumer | `Generic` `1209:4A4F` | `SdlCompatible` `045E:02FD` |
| --- | --- | --- |
| SDL3 app (Steam, games) | Enumerated; gamepad only with OJD's mapping (CRC-less GUID `03000000091200004f4a000008040000`). Supplied by environment variable for apps OJD launches and by a mapping file the CLI prints or exports. | Not listed with default hints (live evidence); needs the hardware-evidenced fix. |
| GameController framework | Seen as a generic HID gamepad. | `supportsHIDDevice` yes, "Xbox Wireless Controller", category "Xbox One", haptics yes. |
| Wine and CrossOver | Seen as a generic HID joystick (task: hardware check, not claimed here). | Seen as Xbox-class where Wine's SDL path lists it. |
| Browsers | W3C Gamepad API non-standard mapping unless the browser has a rule for the ID; OJD publishes a W3C-style description. | Standard mapping expected through the Xbox ID. |

The browser and Wine rows are expectations to verify by the hardware checks, not facts. The mapping line follows the published button usages pinned by `GenericGamepadHIDTests.normalizedButtonsSerializeToTheirPublishedUsages`; SDL accepted the format live, and the button order awaits a hardware re-check:

```text
03000000091200004f4a000008040000,OpenJoystickDriver Generic HID Gamepad,a:b0,b:b1,x:b2,y:b3,leftshoulder:b4,rightshoulder:b5,back:b6,start:b7,leftstick:b8,rightstick:b9,dpup:b10,dpdown:b11,dpleft:b12,dpright:b13,guide:b14,misc1:b15,leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:+a4,righttrigger:+a5,platform:Mac OS X,
```

`ojd virtual show --json` gains `sdl: { guid, mapping }` and `w3c: { ... }`; `ojd virtual export-mapping --format sdl|w3c` writes them. Submitting the mapping to SDL_GameControllerDB or upstream is an outward-facing decision of the user and is not in tasks. A new pid.codes entry for a layout that matches the W3C standard mapping directly is an open question.

### D7 Device matching and same-ID clones

A record `modes[]` entry matches on any of: link kind, interface signature (class, subclass, protocol, endpoint set, HID usage page and usage), manufacturer and product strings, `bcdDevice` range, and read-only probes. A probe is a `getReport` of a named feature report with an expected answer, a stall, or a byte pattern; probes never write.

Live evidence (2026-10-14): two `054C:0268` DS3 (locations `01130000`, `01140000`) have identical strings, `bcdDevice 0100` and 148-byte descriptor, but differ in feature reports:

| Report | Location 01130000 | Location 01140000 |
| --- | --- | --- |
| `0xEF` | stall `0xE0005000` | answers |
| `0x01`, `0xF2`, `0xF5`, `0xF7`, `0xF8` | differ | differ |

Which location is the genuine Sony CECHZC2E is open (question 1); `0xEF` is the candidate discriminator. The genuine one is the user's unit with rumble; the clone is the "other clone mentioned in wiki" (not GP100). Because decision 5 says clone behavior is hit-or-miss until someone tests, the first task builds the mechanism and the hardware check validates it.

DEXT matching is generated from records whose route is `ExtensionOwned`, limited to the seven granted IDs (`045E:02D1`, `02DD`, `02E3`, `02EA`, `0B00`, `0B0A`, `0B12`). `Scripts/Signing/doctor.py`, `configure.py` and `Scripts/Build/driverkit.sh` enforce the set today and keep enforcing it. A record asking for the extension outside the set fails `./Scripts/ojd check driverkit`. More IDs need a new Apple request (user's call).

DS3 over Bluetooth: macOS 27 asks for a PIN the DS3 lacks; macOS 12 pairs. The host-address write (`ojd controller pair --host-address auto`) is added and verified on the A1398.

### D8 Identity naming

| New name | Replaces | Meaning |
| --- | --- | --- |
| `ControllerModelID` | model-only use of `DeviceIdentifier`, `RecordIdentity`, `OJDControllerRecordIdentity`, `PhysicalHIDIdentity` | Which record |
| `ControllerHardwareIdentity` | `ControllerIdentity` | Model plus optional serial number |
| `ControllerConnectionAddress` | `locationID`, `interfaceNumber`, `USBTransportServiceIdentity`, Switch 2 synthetic locations | Enum: `ioKit(locationID, interfaceNumber?)`, `usbService(route, serviceID)`, `gattPeripheral(UUID)` |
| `LogicalControllerID` | `DeviceIdentifier` (full use) | Hardware, address, optional role |
| `ControllerSessionToken` | `runtimeIdentifier` (`E-...`), `M-` fallback dropped | One attachment |
| `ControllerPortKey` | `UnitIdentity` (`U-...`), `VirtualHIDProfileOverrideStore.Identity` | Stable user-facing slot |
| `ControllerReference` | `ControllerSelection`, `ControllerSelector`, `RuntimeDeviceSelector` | `.session`, `.port` or `.model`; one parser for CLI, GUI and RPC |

`PhysicalDevice` and `PhysicalInterfaceSignature` keep their names. `UnboundDeviceKey`, `HIDInitializationKey` and `USBTransportModel` are reviewed in the same pass. Footprint: `DeviceIdentifier` 1012 references in 248 files (84 in Sources, 164 in Tests; the CLI audit counted 1022), 22 model-only construction sites, `runtimeIdentifier` 474, `RuntimeDeviceSelector` 105, `ControllerIdentity` 94. The renames go in the dependency order of task groups 3 to 6.

### D9 CLI

Follows clig.dev plus Apple conventions; global flags `--json --plain -q --no-color --no-input --timeout` stay. Existing groups stay: `status`, `permission`, `service`, `controller`, `virtual`, `profile`, `binding`, `config`, `record`, `mod`, `access`, `setting`, `update`, `log`, `diagnose`, `explain`; `extension` becomes `transport-extension`.

| Old | New |
| --- | --- |
| `controller ownership native\|virtual`, `outputOwner macos\|ojd`, record `ownership` | `controller claim <ref>` / `controller release <ref>`, record field `server` |
| `ownership.physical` `driverKitOwnedUSB`, `nativeGamepad`, `nativeHIDVisible` | `ExtensionOwnedUsb`, `SystemGamepad`, `SystemHidVisible` |
| `extension` command, kind `DriverExtension` | `transport-extension`, kind `TransportExtension` |
| `usbExtension claims\|doesNotClaim` | `transportClaim claimed\|unclaimed` |
| permission ids `input-monitoring`, `accessibility`, `driver-extension` | `input-read`, `input-inject`, `usb-transport` |
| `identityKind team\|apple`, `teamIdentifier` | `publisher.kind signed\|platform`, `publisher.id` |
| `--app <bundle-id>`, `bundleIdentifier` | `--app <app-id>`, `appID` |
| modifier names `command`, `option` | `meta`, `alt` |
| `diagnose --bundle` | `diagnose --output` |
| `accessBackend ioHID\|ioUSBHost\|usbDriverKit` | `hid\|rawUsb\|usbExtension` |
| `macOSVersion` | `osVersion` plus `osName` |
| `appleGameControllerAudit`, `appleExactDeviceCount`, `appleRecord`, `appleIdentifiers` | `systemGamepadAudit`, `systemExactDeviceCount`, `systemRecord`, `systemIdentifiers` |
| kinds `USBPacket`, `JoyConPair` | `RawReport`, `ControllerPair` |
| socket in `DARWIN_USER_TEMP_DIR` | runtime-directory port |
| endpoint `as: hid-xbox-one-s-bt` | persona ids |

New: `ojd virtual export-mapping`, `ojd setting` keys for every GUI-only switch (per-event notifications, Send Test Notification, Copy Support Report as `diagnose` on stdout, which the GUI copies), a settings file schema (settings move out of `UserDefaults` into layered files), and a single `DataDirectory` port that every store uses. The CLI target imports the Service in 9 files and USB in 2; the neutral core is split from a macOS host adapter so that `Sources/OpenJoystickDriver` has no macOS-only imports outside `platform`. The command tree is checked by a test that lists every command and flags any without a GUI place (D10).

Command-line tool link (open item 4, user decision 2026-10-15): the app owns the link, as other macOS apps that ship a tool do (an Install Command Line Tool action that asks for an administrator password to write `/usr/local/bin`). The app installs and removes it from the Settings Command Line pane; `ojd` does not install or remove it and only reports whether it is installed, in `ojd status`.

Facts that go to docs: `docs/development/wire-protocols.md:20,22` is stale; `source-topology.md` lists a nonexistent `CLI/Catalog/`; the stale backend id `gameControllerHID` is removed.

### D10 Coverage matrix: CLI to menu bar to GUI

CLI is a subset of GUI (every command has a GUI place); the menu bar is a subset of GUI.

| CLI group | GUI area | Main menu | Status item |
| --- | --- | --- | --- |
| `status`, `transport-extension`, `permission`, `service` | Status | View > Status (`Command-1`) | status line, Open Window |
| `controller`, `virtual`, `config show` | Controllers (list, detail, Input Test, persona, serving) | Controller menu | Controllers submenu |
| `profile`, `binding` | Profiles | Profile menu, File > Import/Export Profile | Profiles submenu |
| `record`, `mod` | Library | File > Install Record or Mod | none |
| `access` | Access | none | Grant Access |
| `log`, `diagnose`, `explain` | Activity | File > Save Support Report, Save Activity Log; Help | Help submenu |
| `setting`, `update` | Settings window | App > Settings | Settings |

### D11 GUI

The GUI is redone entirely as an AppKit shell for macOS 12: `NSSplitViewController`, `NSToolbar`, `NSStatusItem` with `NSMenu`, `NSWindowController` for Settings; SwiftUI content inside `NSHostingController`. `NavigationSplitView`, `MenuBarExtra` and `Window` need macOS 13, and `.inspector` needs macOS 14, so they are not used. `NSToolbarItemGroup` `selectOne` and `NSTrackingSeparatorToolbarItem` (macOS 11) are available.

- Main window: toolbar = sidebar toggle + area buttons Status, Controllers, Profiles, Library, Access, Activity. Window title is the current area. `Command-1` to `Command-6` select areas. Confirmations are window-modal sheets. Errors use one inline pattern (symbol, text, Details revealing `ojd explain`).
- Settings window: the `6858be2e` pattern (an `NSToolbarItemGroup` `OpenJoystickDriver.SettingsPanes`, `selectOne`, expanded, icon and label, no customization, per-pane minimum sizes) with panes General (launch at login, show in menu bar, updates), Notifications, Command Line, Advanced (developer tools).
- Apple HIG pages followed: Toolbars, Sidebars, Segmented controls, Tab views, Settings, Windows, The menu bar.
- Known bugs the rebuild must not reproduce: uninstall alert shows repair text (`SetupCard.swift:64-70`); sidebar toggle labelled "Settings navigation" (`WindowController.swift:196-204`); window titled with app name (`:85`); orphan `saveSupportReport`/`saveSupportLogs` actions (`MenuBarCoordinator+ApplicationMenu.swift:121-142`); hard-coded English `sharingWarning` (`ApplicationServiceLogService.swift:39-41`); `wiki/Using-the-App.md:160` names nonexistent `app login disable`; "Controller Test" button only switches pane; Copy Support Report gives no feedback; CLI-tool uninstall has no confirmation; Bluetooth detected by comparing the English string "Bluetooth" (`ControllerDetailView+Facts.swift:64-66`, `MenuBarCoordinator+Lifecycle.swift:325`); status line built by joining with " · " (`MenuBarViewModel.swift:24-52`).
- Visual design: `/impeccable` passes with 13 reference screen groups (shell, Status, Controllers, Input Test, Profiles, Library, Access, Activity, Settings window, status item, destructive confirmations, errors, main menu), each in light and dark, with a subset under Increase Contrast, Reduce Transparency, larger text, VoiceOver, `de-DE` and `ar-SA`. The user judges each visually; no group is called done without that approval.

### D12 Menu bar

Fixed item set; items are disabled, never hidden. Status item uses a template image. The state comes from the service by notification, with polling only as a fallback (today: 1 s polling).

```text
Status line
Controllers >  Suspend/Resume, Test Input..., Active Profile >, Disconnect Wireless Link... (disabled unless wireless), Show in Window
Profiles >     Activate, Deactivate
Grant Access...
Open Window
Settings...
Help >         Activity Log..., Explain Error Code..., Report a Problem..., Project Website
Quit
```

Main menu: App (About, Settings, Services, Hide, Hide Others, Show All, Quit), File (Import/Export Profile, Install Record or Mod, Save Support Report, Save Activity Log), Edit, View (areas `Command-1` to `Command-6`, Show/Hide Sidebar `Control-Command-S`, Full Screen), Controller, Profile, Window, Help.

### D13 Localization

Keep `.strings` and `.stringsdict` (option A). `.xcstrings` is not compiled by SwiftPM (tested with a scratch package), so it is rejected. Namespaces as in decision 6, with examples:

| Prefix | Example key |
| --- | --- |
| `term.*` | `term.controller` |
| `action.*` | `action.disconnect` |
| `status.*` | `status.service.running` |
| `ui.<area>.*` | `ui.controllers.empty.title` |
| `ui.menu.*` | `ui.menu.file.saveSupportReport` |
| `ui.extra.*` | `ui.extra.controllers.suspend` |
| `ui.settings.<pane>.*` | `ui.settings.general.launchAtLogin` |
| `a11y.*` | `a11y.sidebar.toggle` |
| `cli.<group>.<command>.*` | `cli.virtual.exportMapping.summary` |
| `error.<code>.*` | `error.E2023.message` |
| `notify.*` | `notify.controller.connected` |
| `platform.<os>.*` | `platform.macos.driverExtension.name` |

Segments are lowerCamelCase. OS-specific words appear only under `platform.*`. Every multi-argument string uses positional specifiers (102 keys lack them today). Every key has a translator comment (none today). The 69 duplicate English values are merged where the meaning is the same, and the roughly 51 Apple-specific values are split into neutral and `platform.*` pairs. Plurals: 5 today; the checker requires a `.stringsdict` entry for every key that takes a count. `crowdin.yml` shape: source `en-US.lproj/*.strings` and `*.stringsdict`; translation `%osx_locale%.lproj/%original_file_name%`. Stop copying `Localizable.template.*` into the bundle. `Scripts/Quality/check_localization_keys.py` is updated for the new prefixes, positional specifiers, plural coverage, comment presence and the key-shape regex. Scale: 1602 keys across 22 bundles (`C`, `en-US` and 20 locales); estimate 3 to 5 engineering days for the re-key alone.

Catalog-wide decisions left open by the earlier review (`06-l10n-review`) go to Open Questions.

### D14 SDK, endpoint and streaming

The public endpoint (today `apiVersion openjoystickdriver.io/v1beta1`, kinds Challenge, Hello, Welcome, Subscription, FeedRequest, FeedSession, Frame, Status; errors E1001 to E1009) moves to `openjoystickdriver/v1alpha1`, is documented in `docs/sdk/`, and ships with a reference client (the repository already has `Tests/RepositoryScripts/test_endpoint_reference_client.py`). Streaming boundary: `InputSource` produces canonical frames and `OutputSink` consumes them; physical controllers, the virtual HID device, the endpoint and WebRTC are plug-ins on that boundary. WebRTC is one transport; signalling is the endpoint's `Subscription` flow. Latency and fan-out limits are stated in the spec, and the existing `.bufferingOldest(64)` queue policy from issue #22 becomes a per-record tuning value.

### D15 Relation to the open issues

Issues the data model must make expressible: #38 (ShanWan vendor control reads, gated by manufacturer string), #41 and #34 (8BitDo Ultimate 2C BLE identify command, mode switching PIDs 301B, 301C, 310A, 310B, 6012, 6013, 901B), #35 and #37 (Flydigi Vader 4 Pro dongle `04B4:2412` vendor report 4), #33, #31, #22 (375 Hz versus 5575 Hz polling, reset loop), #21 (keepalive), #45 (ASUS ROG Raikiri Pro GIP with no packets), #46, #19, #14, #11, #9, #8. Attach and replug robustness (#32, #48, #18, #46, #8) is code, not data. Open pull requests #47, #42, #36 put VID:PID in Swift and are not merged as they stand; #40 and #39 edit generated files and are redone through authored inputs. Facts from other projects are used as facts only.

## Risks / Trade-offs

- [The release is very large and touches nearly every file] -> ordered task groups, each with a Verify line; the equivalence harness comes first.
- [Data-driven records cannot express some protocol] -> keep that protocol as code and give it a typed-parameter record; list it in `protocol-descriptions`.
- [Probe-based clone detection misfires on a firmware revision nobody tested] -> probes are read-only, a failed probe falls back to the model's default mode, and the hardware check covers the two DS3 units.
- [`SdlCompatible` still not opened by SDL] -> it is opt-in and documented as not working with default hints until a hardware-evidenced fix exists.
- [Default persona change surprises users of 0.5.x] -> it is a breaking release; release notes say so.
- [GUI visual quality cannot be machine-checked] -> user approval gates per screen group.
- [Machine-translated strings drift while keys move] -> re-keying is a mechanical rename first; translation review is a separate task.
- [Apple grants only seven USB IDs] -> the generator refuses extension records outside the set.
- [The hardware list has no Wolverine V1 TE or DS4 v2 in the live run] -> hardware checks list each device; the user plugs them in.

## Migration Plan

No migration: 0.5.x user files are rejected with a message that names the file, the found `apiVersion` (or its absence) and the supported one. Release notes list the rejected shapes and tell users to recreate profiles and records. Rollback is not offered; the previous release stays installable.

## Open Questions

1. Which DS3 (`01130000` or `01140000`) is the genuine CECHZC2E? The `0xEF` answer is the candidate discriminator; the user checks by physical marking.
2. Request more `transport.usb` IDs from Apple? (user's call; outward-facing)
3. Catalog-wide localization choices left by the review: French spacing before `: ; ? !` and NBSP, `pt-BR`/`es-MX` quotes (guillemets or curly), `id-ID` instal/pasang, `vi-VN` "mot cach goc", `tr-TR` `cli.mod.list.discussion`, `zh-HK`/`zh-TW` informal versus formal "you" in five strings, `ar-SA` running-service split, German "Endet mit 1" versus "Beendet sich mit 1".
4. Settled 2026-10-15: the command-line tool link belongs to the app; `ojd` only reports it (D9).
5. Do the button and axis directions of the `1209:4A4F` mapping hold under real presses? (hardware check)
6. Register a new pid.codes entry for a layout equal to the W3C standard mapping?
7. Submit the OJD mapping to SDL_GameControllerDB or SDL upstream? (outward-facing; not in tasks)
8. Turn on GitHub Pages for the schema `$id` URLs? (outward-facing; the task prepares it)
