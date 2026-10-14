## Why

The work on `feat/0.6.0-alpha.1` was meant to be `0.5.0-beta.5`, but it grew into a new minor release.
It has breaking CLI output envelopes (`f70a1842`), versioned schemas (`c22baa3b`), the config layers (`82898cbf`), and mod packages.
`Sources/OpenJoystickDriver/App/Info.plist:18` already says `0.6.0-alpha.1`, and no tag has that version yet.
An alpha is not a place for half-built features, so each feature that ships must be complete, tested, and documented.

The mod package feature (`docs/development/cli-config-sdk-plan.md:81-104`, slice 5B) is the part that is not finished.
Slice A (`8b15dfb6`) added the manifest schema, `ModPackageStore`, and the package layer for records and personas.
Slices B1 (E3029, E4008 renumbered to E4007) and B2 (read-only package profiles in `RemappingProfileLibrary+Packages.swift`) were in the working tree, not committed, and B2 had had no code review.
B3 (snapshot and watcher), C (`ojd mod`), and D (sample package and docs) were not started.

This change was converted from the dotclaude spec `.dotclaude/spec/changes/0.6.0-alpha.1/` (`schema: dotclaude-spec/2`, `size: large`, `status: implementing`, `verify: just check`) on 2026-10-14.
Its progress, package metadata, and review state are in `tasks.md`.

## What Changes

- Review and finish B1 and B2, then commit them.
- B3: the remapping snapshot lists package profiles, and the service reloads profiles when `Packages/` changes.
- C: `ojd mod validate|install|list|remove` with `--dry-run`, `--force`, and `--json`, and their output kinds and schema definitions.
- The app and CLI explain E3029 in the user's language instead of the generic error.
- D: the sample package in `docs/sdk/sample/`, `wiki/Writing-Controller-Mods.md`, and the wiki and CHANGELOG updates.
- A review of the machine-translated mod strings under `LOCALIZATION.md`.
- The `[Unreleased]` CHANGELOG section becomes `[0.6.0-alpha.1]`.
- The full check list in `CLAUDE.md` passes on the final tree.
- The native/virtual ownership toggle that issue #46 promises for this release: `ojd controller ownership` and an app control over the existing record `ownership` field (`TransportProfiles.swift:207-214`).
  Today a native controller with a passthrough profile gets no virtual gamepad (#46, the 8BitDo `2DC8:301B` tester report), because only remapping routes fill `observedInputDemand` (`DevicePipeline+InputEvents.swift:57-60`, `RemappingRoutingCore.swift:49-51`).
- The virtual stick stutter that testers report in GameController games, CrossOver, and browsers while the OJD preview is smooth.
- Issue #18: the original Xbox One controller `045E:02D1` is not listed while the XboxUSBDevice extension is active (Intel macOS 15.8.1 and Apple Silicon macOS 26).
- A signing doctor run against the host profiles that the maintainer regenerated with `userclient-access` (`Host.entitlements:16-20` needs it).
  The maintainer installed them on 2026-10-14; they also name `com.openjoystickdriver.VirtualHIDDevice`, so `signing configure` refused them.
- The signing checks accept a host profile whose `userclient-access` list includes `com.openjoystickdriver.XboxUSBDevice` among other IDs (maintainer decision, 2026-10-14); `Host.entitlements` still claims exactly XboxUSBDevice.

Out of scope:

- Restoring the `com.openjoystickdriver.VirtualHIDDevice` DriverKit extension as a second virtual backend (maintainer decision, 2026-10-14). `IOHIDUserDevice` stays the only virtual backend.
- Hardware checks, which need physical controllers and are done by the maintainer.
- The frame double-decode measurement decision.
- Push, CI, tagging, notarizing, `just package-tester`, and publishing; each needs the maintainer's approval.
- App UI that greys out package profiles (`cli-config-sdk-plan.md:116` defers presentation of the new layers).
- Fix D: `cf59d456` closed it. `ProtocolDriverRegistry.swift:30-34` documents why the offline editor is not narrowed, and the CLI and app explain E3026-E3028.
- The user's uncommitted removal of `.agents/skills/` and `skills-lock.json`, and the untracked `.codex/`.

Standing rules: ask before each commit; never push; CHANGELOG entries and wiki paragraphs stay on one line; doc comments wrap at 100 columns; do not edit the generated catalog or DriverKit files; change tests or limits only on request; commit trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
The later user constraints in `tasks.md` "Working agreements" relax "ask before each commit" for the branch `feat/0.6.0-alpha.1`.

## Capabilities

### New Capabilities

- `mod-packages`: installed mod packages, their read-only profiles, runtime `requires` checks, and the `ojd mod` commands (REQ-1 to REQ-10, REQ-17).
- `virtual-ownership`: the native/virtual ownership toggle in the CLI and the app and its live re-apply (REQ-18 to REQ-22).
- `mod-localization`: E3029 explained in the user's language and the review of the mod strings (REQ-11, REQ-12).
- `mod-sdk`: the sample package and the mod documentation (REQ-13, REQ-14).
- `release-readiness`: the dated CHANGELOG section and the full check list (REQ-15, REQ-16).
- `virtual-input-delivery`: virtual stick reports are not delayed or held (REQ-23).
- `usb-device-detection`: `045E:02D1` is listed on the XboxUSBDevice route (REQ-24).
- `driverkit-signing`: the signing checks accept the regenerated host profiles (REQ-25, REQ-26).

### Modified Capabilities

None; `openspec/specs/` was empty when this change was converted.

## Impact

- Kit: `Packages/`, `Protocol/Catalog/`, `Output/`, `HID/`, `Device/`, `ApplicationService/`, `Errors/`, and the 22 localization catalogs.
- Service: remapping profile library, runtime watchers, RPC handlers (new `setControllerOwnership` method).
- CLI: new `ojd mod` group, new `ojd controller ownership`, `controller show` fields, `cli-output.schema.json` `$defs`, new error code E2023.
- USB: `USBDriverKitTransport.swift` reads identity from the parent `IOUSBHostDevice`.
- Presentation: E3029 text, ownership picker.
- Scripts: `Scripts/Signing/configure.py`, `doctor.py`, `Scripts/Build/driverkit.sh`.
- Docs: `docs/sdk/sample/`, `docs/testing/xbox-one-02d1.md`, `wiki/`, `CHANGELOG.md`.
