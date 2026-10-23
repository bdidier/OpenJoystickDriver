# Building From Source

Everything is driven through `./Scripts/ojd`. Run `./Scripts/ojd help` for the route list.

## Prerequisites

- macOS with Xcode installed and launched once, for the macOS SDK and `xcodebuild`. `Package.swift` declares `swift-tools-version:6.4.0` and a macOS 12 deployment floor.
- Swift comes from Xcode's own toolchain, which `.swift-version` names (6.4.0, Xcode 27). Every Swift command of the repository goes through `Scripts/Platform/environment.sh`, which puts `$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin` first on `PATH` and stops when that `swift` is another version, so one compiler writes `.build`. A swift.org toolchain does not fit: from 6.0.1 on, its runtime libraries are built for macOS 13, so linking for the macOS 12 floor prints a linker warning, and a warning fails the build. CI uses Xcode 27.0 on the `xcode-27` runner.
- Homebrew, for the helper tools. In an interactive terminal, each `./Scripts/ojd` route offers to install only the formulas it is missing. `./Scripts/ojd setup` installs `just`, `bun`, `ruff`, `pyright`, `shellcheck`, and `swiftlint`, plus the Git hooks and the pinned Biome (`@biomejs/biome` in `package.json`; husky, commitlint and Biome are all installed through `bun install`).
- Python 3. The dispatcher creates its own schema-validation environment.

Most routes that build or run Swift code require full Xcode, not only the Command Line Tools. The route requirements in `Scripts/Platform/capability_requirements.py` list full Xcode for `check profiles`, `check schemas`, `check driverkit`, `catalog regenerate`, `catalog xpad`, `errors regenerate`, `diagnose record`, `test parsers-macos14`, and every `build` and `release` route. `check profiles`, `check schemas`, `catalog regenerate`, `catalog xpad` and `errors regenerate` build `OJDRepositoryTool`, the Swift executable that is the only validator of controller records, protocol descriptions, profiles and personas and that prints the constants Swift owns, such as the `apiVersion` and the exit statuses of `ojd`. When Xcode is missing, the route prints guidance and stops. Whether a plain `swift build` or `swift test` works with only the Command Line Tools has not been verified.

Clone and set up:

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
./Scripts/ojd setup
```

## What You Can Do With Which Apple Assets

| Assets | Works | Does not work |
| --- | --- | --- |
| None | `swift build`, `swift test`; `./Scripts/ojd check profiles`, `check schemas`, `check driverkit`; `./Scripts/ojd catalog regenerate --check`; `./Scripts/ojd driverkit generate`; `./Scripts/ojd test parsers-macos14`; `./Scripts/ojd diagnose record <json> --validate-only`; the checks in [`CLAUDE.md`](../../CLAUDE.md) | Any `build` route, any install, live USB probes through the DEXT |
| Apple Development identity and the two development profiles | `./Scripts/ojd build dev` (signed app bundle, no DEXT); `build dext` (DriverKit extension embedded into the app in `.build/`); `build install dev` (full rebuild and install); `build install-fast dev` (app-only rebuild, keeps the installed system extension) | `package tester` and `release` routes |
| Developer ID identity, Developer ID profiles, and notarization credentials | `build release`, `build install release`, `package tester`, `release package`, `release install-local` | Nothing more; these are maintainer routes |

Notes on the rows:

- `build dev`, `build dext`, `build install dev`, and `build install-fast dev` require configured development signing (`.env.dev`, both profiles, and matching Keychain identities). Interactively, the dispatcher runs `signing configure` and `signing install-profiles` for you; in a non-interactive run it stops with "signing is not configured".
- The DEXT cannot be ad-hoc signed. `build dext` stops with "DriverKit extensions cannot use ad-hoc signing" when `CODESIGN_IDENTITY` is unset or `-`.
- The host app needs the `com.apple.developer.hid.virtual.device` entitlement. The build rejects a host profile that lacks it. The development profile's device list must also include your Mac, or macOS ignores the entitlement at run time and virtual device creation fails. See [Signing](signing.md).
- The single DEXT, `com.openjoystickdriver.XboxUSBDevice`, carries only `com.apple.developer.driverkit` and the Apple-issued restricted USB entitlement for a fixed set of Microsoft product IDs, and the build rejects a DEXT profile without that exact grant. The app, not the DEXT, publishes virtual gamepads. A development host profile without a `userclient-access` grant for `com.openjoystickdriver.XboxUSBDevice` builds the app without the DEXT. Without the DEXT, contributors can still develop everything that opens USB interfaces from the app through IOUSBHost, and validate records with `--validate-only`.
- `build install-fast dev` needs an earlier `build install dev`; it stops when `/Applications/OpenJoystickDriver.app` is missing.
- After a DriverKit change, a full install can require a reboot. Use `build install-fast dev` while iterating on the app.

Local configuration files are described in [Environment files](environment.md); asset setup is in [Signing](signing.md). Tester DMGs are in [Create a tester build](tester-builds.md), and releases in [Release reconciliation](releases.md).

## Everyday Loop

```bash
swift test
./Scripts/ojd check profiles
./Scripts/ojd build install-fast dev      # needs Apple Development signing
```

`just check` runs the complete validation that CI repeats. The `justfile` lists the commands, and `./Scripts/ojd --help` lists the repository routes.

## Building in Xcode

`OpenJoystickDriver.xcodeproj` builds the app from the Swift package.
Open it in Xcode and build or run the `OpenJoystickDriverApp` scheme.
The `build` routes run the same scheme through `xcodebuild`, because only an Xcode build extracts the App Intents metadata that Shortcuts reads.

An Xcode build is signed to run locally, without the restricted entitlements in `Sources/OpenJoystickDriver/App/Host.entitlements`.
Without the `com.apple.developer.hid.virtual.device` entitlement, it cannot create the virtual gamepad.
Use `./Scripts/ojd build install-fast dev` to test the signed app.

When a swift.org toolchain is selected through `TOOLCHAINS`, `xcodebuild` cannot resolve the package.
The `build` routes unset `TOOLCHAINS`; in a shell, run `env -u TOOLCHAINS xcodebuild`.
