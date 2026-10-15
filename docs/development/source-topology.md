# Source Topology

OpenJoystickDriver splits the package into SwiftPM targets whose dependencies enforce the layering, and into capability directories inside each target. Source and test paths name durable owners; generated DriverKit output is never source.

## Targets

| Target | Owns |
| --- | --- |
| `OpenJoystickDriverKit` | controller domain, HID/USB ports, parsers, profiles, policy, shared RPC contracts |
| `OpenJoystickDriverUSB` | IOUSBHost/USBDriverKit facade and restricted DEXT configuration |
| `OpenJoystickDriverService` | runtime RPC server, output dispatch, remapping library/routing/system events, status, diagnostics |
| `OpenJoystickDriverCLI` | command grammar and command implementations; neutral, reaches macOS through `PlatformHost` |
| `OpenJoystickDriverPresentation` | AppKit lifecycle and SwiftUI user flows |
| `OpenJoystickDriverMacOSHost` | macOS host adapter: `MacOSPlatformHost` conformance and the headless application host |
| `OpenJoystickDriver` | executable: main, host installation, App Intents, bundle resources |
| `DriverKitGenerator` | build-time generated native-project entry point |
| `OpenJoystickDriverHIDTool` | internal hardware investigation executable |
| `OpenJoystickDriverGameControllerProbe` | isolated GameController visibility probe |

## Dependency Graph

`Package.swift` declares these dependencies; the compiler rejects any import outside them.

```text
Kit
USB                       -> Kit
Service                   -> Kit, USB
CLI                       -> Kit
Presentation              -> Kit
MacOSHost                 -> Kit, USB, Service, Presentation
OpenJoystickDriver        -> Kit, Service, CLI, Presentation, MacOSHost
DriverKitGenerator        -> USB
HIDTool                   -> Kit, USB
GameControllerProbe       -> Kit
```

- Presentation depends on Kit only. It reaches the runtime through its `ApplicationServiceGateway` protocol (implemented by `ApplicationServiceClientGateway` over the Kit RPC client) and injected closures, so it never imports Service, CLI, or USB.
- The CLI depends on Kit only. Kit declares the `PlatformHost` protocol and the `PlatformHosts` registry. The executable installs `MacOSPlatformHost` from `OpenJoystickDriverMacOSHost` at launch, and the CLI calls `PlatformHosts.current` for extension status, activation, USB scanning, and entitlement checks. A command run without an installed host stops on a precondition.
- Only `OpenJoystickDriverUSB`, `DriverKitGenerator`, and their tests import SwifterKit. Kit owns stable Sendable transport values and protocols; USBDriverKit, IOUSBHost, and SwifterKit lifetimes stay in USB.
- The headless host in the executable owns one `ApplicationServiceRuntime`, which starts the authenticated RPC server; both types live in Service.

## Directory Owners

```text
Sources/OpenJoystickDriverKit/
  ApplicationService/  shared client, RPC, payload, lifecycle, and remapping contracts
  Bluetooth/           Switch 2 Bluetooth LE routing
  Concurrency/         locking and blocking-work helpers
  Platform/            `PlatformHost` protocol and `PlatformHosts` registry
  Device/              controller identity, Manager, Discovery (HID, USB), input state,
                       PhysicalOutput, Pipeline
  Diagnostics/         support reports, probes, health, build identity, and packet logs
  Errors/              the `ErrorCode` catalog
  HID/                 availability-selected physical HID access
  Localization/        string lookup over the bundled locale tables
  Output/              availability-selected virtual HID, backends, reports, formats, and profiles
  Packages/            mod package manifest, validation, and the installed-package store
  Permissions/         app permission policy
  Process/             bounded external process runner and the command-line tool link status
  Protocol/            catalog, GIP, parsers, drivers, classification, and physical-output
                       capabilities
  Remapping/           reusable profile and mapping engine
  Resources/           generated controller records (Controllers/) and localization tables
  Settings/            the `Settings.json` store, document, and legacy-defaults import (defaults, then the user file)
  Storage/             DataDirectory port and its macOS implementation; the only path builder
  Update/              release version parsing and update checking

Sources/OpenJoystickDriverUSB/
  Configuration.swift  restricted DEXT USB configuration
  PassiveProbe/        passive USB registry and descriptor probing
  Transport/           IOUSBHost and USBDriverKit transports

Sources/OpenJoystickDriverService/
  Remapping/           Profiles (library and persistence), Routing, SystemEvents
                       (CoreGraphics adaptation)
  Runtime/             runtime composition, Automation, Endpoint, OutputDispatch, RPC, file
                       watchers, and virtual device diagnostics
  Status/              SystemExtension status

Sources/OpenJoystickDriverCLI/
  Commands/            one directory per command group: Access, Binding, Config, Controller,
                       Diagnose, Explain, Extension, Log, Mod, Permission, Profile, Record,
                       Service, Setting, Status, Update, Virtual
  Root/                global options, failure and terminal handling, service connection

Sources/OpenJoystickDriverMacOSHost/
  MacOSPlatformHost.swift, HeadlessApplicationHost.swift

Sources/OpenJoystickDriverPresentation/
  Components/  Controllers/  InputCapture/  MenuBar/  Profiles/  Runtime/  Settings/

Sources/OpenJoystickDriver/
  main.swift, App/ (Info.plist, Host.entitlements), Resources/
  platform/macos/      PlatformHostInstallation.swift and the App Intents (compiled into the app target for discovery)
```

The neutral targets are `Sources/OpenJoystickDriverCLI` and the executable's files outside `Sources/OpenJoystickDriver/platform`. Each has an import allow-list in `Scripts/Quality/check_neutral_core_imports.py`: the CLI may import ArgumentParser, Darwin, Dispatch, Foundation, Glibc, and Kit; the executable may import Dispatch, Foundation, CLI, and Kit. Any other import or `canImport` fails, including `@_exported` and kinded imports, and block comments are skipped. `Tests/RepositoryScripts/test_neutral_core_imports.py` covers the script, and CI, `just`, and the AGENTS.md check list run it directly. Kit is macOS-bound and out of scope.

Kit `Diagnostics/` holds reports and health types that both the CLI and app read.

## Tests

Each test target mirrors its source target and directory names: `Tests/OpenJoystickDriverKitTests/`, `Tests/OpenJoystickDriverUSBTests/`, `Tests/OpenJoystickDriverServiceTests/`, `Tests/OpenJoystickDriverCLITests/`, and `Tests/OpenJoystickDriverPresentationTests/`. A test for `Sources/<Target>/A/B/File.swift` lives in `Tests/<Target>Tests/A/B/`. Shared fixtures live in `Tests/OpenJoystickDriverTestSupport/` (depends on Kit) and `Tests/ProtocolPacketFixtures/`; `Tests/ParserCompatibilityHarness/` backs `./Scripts/ojd test parsers-macos14`. Add behavior tests, not source-text substring tests.

## Naming and Limits

Extension files are `Type+Concern.swift`, where `Concern` is a noun phrase naming the content, such as `+Queries`, `+Parsing`, or `+Lifecycle`. Delete empty extension stubs.

`python3 Scripts/Quality/check_swift_file_length.py` checks every Swift file under `Sources` and `Tests` that Git tracks or that is untracked and not ignored. It fails when:

- a file has more than 500 code lines under `Sources`, or more than 1000 under `Tests`. Code lines are lines with Swift code; blank lines and comment-only lines do not count, and multiline string content does.
- the concern after the last `+` is exactly `Behavior` or `Scenarios`, or ends in a digit (`+Behavior2`, `+Scenarios1`). These names hide what a file owns.

## Rules

- Give each capability one canonical owner; retain no aliases, forwarding files, or old entry points.
- Keep Kit independent of SwifterKit and of app, runtime, and platform composition.
- Put IOUSBHost/DriverKit adaptation in USB; keep parsing in Kit.
- Use IOKit HID (`IOHIDManager`, `IOHIDDevice`, `IOHIDUserDevice`) on every supported macOS; HID has no OS-version branch and the package does not link CoreHID.
- Never edit or commit `.build/driverkit/generated/`; regenerate with `./Scripts/ojd driverkit generate` and validate with `./Scripts/ojd check driverkit`.

## Rejected Alternatives

- Directories only, no target split. Layering stayed unchecked and eroded: a Status to CLI dependency appeared. Target dependencies make the compiler reject such imports.
- More services or processes. No independent deployment or scaling need exists; the app hosts one runtime.
