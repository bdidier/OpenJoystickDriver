# Contributing

## Setup

```bash
git clone https://github.com/xsyetopz/OpenJoystickDriver.git
cd OpenJoystickDriver
./Scripts/ojd setup
just check
```

Run the needed command and follow its native prompts. The dispatcher automatically creates repository-local Python environments. In interactive terminals, it offers to install only that command's missing Homebrew formulas. Homebrew, Xcode, Apple-issued assets, credentials, system permissions, publication, destructive writes, and hardware actions retain their official or explicit authorization flows. CI never prompts or installs host software.

Git hooks come from husky, installed by `bun install` (run through `./Scripts/ojd setup` or `./Scripts/ojd hooks install`), which points `core.hooksPath` at the main checkout's `.husky/_` by absolute path so every worktree runs the hooks. Run the install in the main checkout first; `./Scripts/ojd hooks validate` reports a relative or missing hooks path. The pre-commit hook formats the staged `*.json` and `*.jsonc` files with Biome (`biome.json`), then runs fast structural checks against the exact staged snapshot. The pre-push hook checks the outgoing tree diff for whitespace errors without repeating lint, builds, tests, or network-backed catalog generation. Run `just check` before opening a pull request; CI repeats the complete validation.

Commit messages must follow Conventional Commits, enforced by commitlint with `@commitlint/config-conventional` in the `commit-msg` hook and in CI on pull requests. Use `type(scope): subject` with a lowercase subject. The header and each body line must be at most 100 characters. Merge commits use `Merge <branch> into <target>`.

Prerequisites and what works without Apple assets: `docs/development/building-from-source.md`. Signing: `docs/development/signing.md`. Releases and packaging: `docs/development/releases.md`. Script routes: `Scripts/README.md`. Dev install: `./Scripts/ojd build install dev`. Do not edit `.build/driverkit/generated/`. SwifterKit comes from the `Package.resolved` remote; `OJD_USE_LOCAL_SWIFTERKIT=1` builds the sibling `../SwifterKit` working tree instead, which CI and release builds reject.

Create a private, notarized DMG with the [local tester-build guide](docs/development/tester-builds.md).

```bash
./Scripts/ojd diagnose record /tmp/controller-candidate.json --validate-only
./Scripts/ojd diagnose backends --seconds 5
ojd diagnose --bundle support-report.json
```

`--validate-only` needs no Apple Developer membership. A live USB probe may need the signed app and DEXT. Capture notes: `docs/testing/controller-record.md`. Review product names before attaching a report.

Open tasks: [issues](https://github.com/xsyetopz/OpenJoystickDriver/issues).

## Adding a Controller

1. `system_profiler SPUSBDataType`. `bDeviceClass` `0xff` is vendor-specific (often GIP); `0x03` is HID.
2. Do not hand-edit generated records. Update the pinned importer, or add `Resources/Controllers/<vid>/<vid>-<pid>.json` (a `Controller` for a model no pinned source knows) or `Resources/ControllerPatches/<vid>/<vid>-<pid>.patch.json` (a `ControllerPatch`). Decimal JSON, no display names, no protocol defaults. Then:

   ```bash
   ./Scripts/ojd catalog regenerate --write
   ./Scripts/ojd catalog regenerate --check
   ```

   Source rules: `docs/development/xpad-import.md`.
3. New protocol only: driver in `Sources/OpenJoystickDriverKit/Protocol/Drivers/`, `PhysicalProtocolDriver`, tests under `Tests/OpenJoystickDriverKitTests/`.
4. Check:

   ```bash
   ./Scripts/ojd check profiles
   swiftlint lint --no-cache --strict
   swift test
   ```

## Code Rules

Toolchain: `.swift-version` and `Package.swift`. Warnings are errors. Justify `nonisolated(unsafe)` on the same line.

Style: `.swift-format` and `.swiftlint.yml`. Do not copy them here. Do not add SwiftLint rules that fight the formatter. Run `swift-format` and SwiftLint directly, with SwiftLint `--no-cache --strict`. No `// swiftlint:disable` except an `@objc` callback that cannot comply, with the reason on that line.

GUI and CLI copy: `LOCALIZATION.md`. Tests check codes, routes, identifiers, paths, and structure — not help text, and not `.swift` source via `String(contentsOf:)`.

- Decimal integers in JSON. No hex.
- Keep the existing `print` diagnostics. No new logging stack.
- Parser errors stay local: log and skip.
- Deployment floor: macOS 12. Future iOS and iPadOS companion apps: iOS 15 and iPadOS 15.
- Kit has no SwifterKit. USB adapter: `Sources/OpenJoystickDriverUSB/`. Generator: `Sources/DriverKitGenerator/` and `Scripts/Build/driverkit.sh`.
- No manual DriverKit build or post-generation patch. `./Scripts/ojd check driverkit`.
- The host profile's `com.apple.developer.driverkit.userclient-access` list must include `com.openjoystickdriver.XboxUSBDevice` and may name other bundle IDs; `Host.entitlements` claims exactly `com.openjoystickdriver.XboxUSBDevice`.
- `com.openjoystickdriver.XboxUSBDevice` is the only DEXT. It has one personality, `XboxUSB` (Microsoft GIP USB interfaces), and only the `com.apple.developer.driverkit` and `com.apple.developer.driverkit.transport.usb` entitlements. `./Scripts/ojd driverkit generate [path]` generates it. The app and service publish virtual gamepads through `IOHIDUserDevice`, which needs `com.apple.developer.hid.virtual.device` on the app profile; that entitlement never goes in the DEXT.

## Pull Requests

Submit one logical change. Fill every section of the pull request template. List checks run and whether you tested on your own hardware.

## Issues and Pull Requests

Use the issue forms. Each form has a human variant and an **(AI Agent)** variant with the same fields. Pull requests have one template with an **AI Agent** section.

Write exact values. Vague or missing details get the issue sent back. A bot closes an issue whose version field does not name an exact build, and reopens it when you correct the field.

- Version: the whole line from **About OpenJoystickDriver**, for example `0.6.0-alpha.1+build.1.8.74.sha.08bc747d93f6.dirty (1.8.74)`. Not `alpha`, `beta`, or `latest`.
- macOS: version and build from `sw_vers`, for example `15.6.1 (24G90)`.
- Controller: model name, VID:PID, and connection.
- Steps: numbered, one action each.
- Results: what you saw, with error text and codes copied exactly. Not "doesn't work".
- Anything nobody checked: `Not checked`.

## AI Agents

A human operator stands behind every issue, comment, and pull request an agent writes. The operator reads it before it is posted, and the form names them.

Attribution:

- Keep the attribution your harness adds to commits and pull requests. Do not remove or change it.
- If the harness adds none, end each commit message with a trailer that names the model, such as `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- The human operator stays the commit author.

Writing:

- Say it plainly and briefly. Use the words a user would use. Do not use jargon to sound exact.
- No preamble, recap, extra headings, or emoji. Fill the fields and stop.
- State only what a command, the source, or the operator showed. Do not guess. Write `Not checked` instead.

A fix that the operator tried and tested on their hardware comes with a prompt for the maintainer's agent. Put it in a code block. Use numbered steps that another agent can follow without guessing: each file, the exact change, each check to run, and the result to expect.

```text
Fix: <what is wrong, for which controller, VID:PID, and connection>.
Tested by @<operator> on OpenJoystickDriver <full version>, macOS <version and build>.

1. In <path>, in <function or type>, replace <exact old code> with <exact new code>.
2. Run <command>. Expect <result>.
3. Change nothing else.
```

These rules draw on GitHub's [issue form syntax](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-githubs-form-schema), the [Ghostty AI policy](https://github.com/ghostty-org/ghostty/blob/main/AI_POLICY.md), the Linux kernel's [AI coding assistants guide](https://docs.kernel.org/process/coding-assistants.html), and the [KubeVirt AI contribution policy](https://github.com/kubevirt/community/blob/main/ai-contribution-policy.md).

Report security problems privately, as [`SECURITY.md`](SECURITY.md) describes.

Layout: `docs/development/source-topology.md`. RPC payloads: `Sources/OpenJoystickDriverKit/ApplicationService/`. CLI help: the `CommandConfiguration` of each command under `Sources/OpenJoystickDriverCLI/Commands/`, with its text in the localization strings. `OpenJoystickDriverHIDTool` is internal.
