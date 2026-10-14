## Context

See `proposal.md` - Why.
This design was converted from `.dotclaude/spec/changes/0.6.0-alpha.1/design.md`; its sections are kept verbatim under "Decisions", one heading level lower.
References such as REQ-1 name the requirements in `specs/`, and P1 to P15 name the task groups in `tasks.md`.

## Goals / Non-Goals

**Goals:**

- Finish slice 5B of `docs/development/cli-config-sdk-plan.md:81-104` and the added scope of `proposal.md`, each feature complete, tested, and documented.
- Keep shared files (catalogs, `cli-output.schema.json`, `CHANGELOG.md`, the wiki) with one owner per wave.

**Non-Goals:**

- See `proposal.md` "Out of scope".

## Decisions

### Approach

The change finishes slice 5B in the order of `docs/development/cli-config-sdk-plan.md:81-104`: review and fix B2, then B3 (snapshot and watcher), then C (`ojd mod`), the E3029 presentation, D (sample package and docs), the l10n review, and the full check list.
Eight packages run in six waves.
A shared file (catalogs, `cli-output.schema.json`, `CHANGELOG.md`, the wiki) has one owner in each wave.
No package commits or pushes.
The maintainer approves each commit at the boundaries in "Commit points".

Items marked "unverified" were not read while this design was written.
The package that touches each one reads it first and stops to report when the item is not what the design assumes.

### B2 review (REQ-1, REQ-2, REQ-3)

Code reviewed: the working-tree `git diff` of `RemappingProfileLibrary.swift`, `+Operations`, `+Persistence`, `+Recovery`, and the untracked `RemappingProfileLibrary+Packages.swift` (all in `Sources/OpenJoystickDriverService/Remapping/Profiles/`).

- Replace safety (REQ-3): no defect. `replace(with:)` (`+Persistence.swift:58-81`) writes only `proposed.profiles` and deletes only `profileURL(id)` (`RemappingProfileLibrary.swift:84-86`, which is `Profiles/<uuid>.json`) for ids in `current.profiles`. `current.profiles` is `RemappingProfileLibraryState.profiles`, which never holds a package profile, because `loadIfNeeded` (`+Persistence.swift:8-54`) keeps package profiles in the separate `packageProfiles` property (`RemappingProfileLibrary.swift:64`).
  Package files are in `Packages/<name>/Profiles/<file>`, which no write path names.
- Count limit (REQ-3): no defect. `validate(_ library:)` (`+Persistence.swift:140-143`) counts `library.profiles` only.
- Rollback (REQ-3): no defect for files. `restore(_:)` (`+Recovery.swift:103-127`) touches `Profiles/` files, `ActiveProfiles.json`, and the permissions of the directory only.
  Side note, not a REQ defect: `restore` resets `library` but not `packageProfiles`, so a package reload between `checkpoint()` and `restore` keeps the newer package list.
  That is the wanted state, because the folder on disk is the newer one.
- Read-only check order (REQ-1): no defect. `requireNotPackageProfile` runs before `requireRecoveredLibrary` in `create` (`+Operations.swift:46`), `requireCurrent` (`:62`), `update` (`:77`), `importProfile` (`:105`), and `delete` (`:133`).
  It runs before any `replace`.
- Clash rules (REQ-2): no defect in the code. `ModPackageStore.list()` (`ModPackageStore.swift:41-67`) sorts folders by name, `loadPackageProfiles` (`+Packages.swift:22-41`) walks `manifest.profiles` in manifest order and keeps the first id or name, and `servedPackageProfiles` (`+Packages.swift:45-54`) drops any package profile that a user profile shadows by id or case-insensitive name.
  The test file has no case for a user profile that shadows by name only, or for two packages that share a name; P1 adds both (new tests only).
- Selection from a removed package: no defect. `loadIfNeeded` filters the decoded selections through `allProfiles(..., packageProfiles: packaged)` (`+Persistence.swift:31-43`), so a selection of a removed package profile is dropped in memory, as for a missing user profile. `ActiveProfiles.json` keeps the entry until the next selection write, as for a missing user profile.
- Defect 1, silent skip: `loadPackageProfiles` (`+Packages.swift:31-34`) skips an unreadable or undecodable package profile file with no diagnostic. `CONTRIBUTING.md` says "Parser errors stay local: log and skip", and `discardLegacyLibrary` (`+Recovery.swift:67-76`) shows the `[Profiles]` `print`/`fputs` form.
  Fix: write one `fputs("[Profiles] ...", stderr)` line for each skipped file, with the package name and the file name.
  Do not add a new logging stack.
- Defect 2 (to confirm in P1): a package profile is served without `validate(_:in:)` (`+Persistence.swift:130-138`), while a user profile goes through it (`+Persistence.swift:20`).
  It is unverified whether `RemappingProfileFileStore.load(from:)` already runs `profile.validate()`.
  P1 reads it.
  If it does not, P1 calls `profile.validate()` in `loadPackageProfiles` and skips an invalid profile with the same log line.
- Defect 3: not real. `maximumProfileCount` is enforced only in `+Persistence.swift:141` on `library.profiles`; no payload decoder checks it (`grep -rn maximumProfileCount Sources`, checked while this design was written).
- Directory identity: no defect. `RemappingProfileLibrary.defaultDirectory` (`RemappingProfileLibrary.swift:68-73`) and the parent of `ControllerRecordSet.userDirectory` (`ControllerRecordSet.swift:156-162`) are both `<AppSupport>/OpenJoystickDriver`, so `packagesDirectory` equals `ModPackageStore.rootDirectory`, which the persona watcher (`ApplicationServiceRuntime.swift:178-192`) and `ControllerRecordWatcher.swift:36` also watch.
  P1 adds a test that the two URLs are equal.

### `requires` at runtime (REQ-17, maintainer decision D1: skip and list)

- Today `requires` is checked only in `ModPackageStore.validate` (`ModPackageStore+Validation.swift:40-56`); `list()` (`ModPackageStore.swift:41-67`) does not check it, so all three layers keep serving a package after an OJD update leaves its range.
- Fix in one place: `list()` checks `manifest.requires.admits(running)` against `runningVersion` (`ModPackageStore.swift:31-38`).
  A package outside its range keeps its `manifest`, so `ojd mod list` can print its name and version, and gets `problem` set to the E4002 `requiresExcludesVersion` text that `validate` builds (reuse that text; do not write a second copy).
- Each layer then skips a package whose `problem` is not nil, not only one whose `manifest` is nil:
  - Records: `ControllerRecordSet+Packages.swift:29-40` guards on `manifest`; change it to skip and list when `problem != nil`, so `ojd record list` and `ojd status` show the reason.
  - Personas: `VirtualHIDProfileOverrideStore.swift:216-217` reads `package.manifest?.personas`; skip a package with a `problem` and add one `VirtualPersonaFile` with that problem for its `mod.json`, so `skippedPersonas` in `ojd status` names it.
  - Profiles: `loadPackageProfiles` (`+Packages.swift:22-41`) skips the package with the `[Profiles]` log line.
- `ojd mod list` (P3) prints each package's `problem`.
- Running version that does not parse: `ApplicationVersion.current` is the `CFBundleShortVersionString` of `Bundle.main` (`BuildIdentity.swift:29-33`).
  Under `swift test` and `swift run` it is `unknown` or the xctest plist's `16.0`, and neither parses as `SemanticVersion` (`SemanticVersion.swift:27`).
  `install` and `validate` keep refusing in that case (`ModPackageStore+Validation.swift:43-48`), but `list()` treats an unparsable running version as a development build and admits every package, so a development build serves installed packages and the existing fixtures (`ModPackageLayeringTests`, `ProfileLibraryTests+Packages.swift:192`, `ModPackageFixture.swift:88`, all `minimum 0.6.0`) keep passing unchanged.
  A shipped app always has a SemVer `CFBundleShortVersionString` (`Info.plist:18`).
- Version injection for tests: `ControllerRecordSet.packageRecords(in:)`, `VirtualHIDProfileOverrideStore.init`, and the profile library build `ModPackageStore` with the default version (`ControllerRecordSet+Packages.swift:29`, `VirtualHIDProfileOverrideStore.swift:85-87`, `RemappingProfileLibrary+Packages.swift:26`).
  Each gains a `runningVersion: String? = nil` parameter that it passes to `ModPackageStore(directory:runningVersion:)`; `nil` keeps today's default, so no caller changes.
  The new tests pass a version outside the range, such as `9.0.0`.
- Clash checks: a package with a `problem` is not served, so it does not hold claims. `validate` (`ModPackageStore+Validation.swift:63-66`) counts another package only when its `problem` is nil, so an out-of-range package never blocks the install of its replacement or of another package.

### B3: snapshot and watcher (REQ-4, REQ-5)

- Add `packageProfiles: [ApplicationServiceRemappingPackageProfile]` (`{profileID: UUID, package: String}`) to `ApplicationServiceRemappingSnapshotPayload` (`ApplicationServiceRemappingRPC.swift` ~283-337, unverified line range).
  Decode it with `decodeIfPresent(...) ?? []`, as REQ-4 requires.
  This is an RPC payload default, not a schema-document fallback, so the no-shim rule of `Resources/Schemas/AGENTS.md` does not apply.
- Fill it in `makeSnapshot` (`RemappingRequestCoordinator+Operations.swift` ~194, unverified) from `RemappingProfileLibrary.packageProfileSources()` (`+Packages.swift:66-73`), sorted by profile id.
- CLI JSON: P2 checks whether a CLI command prints this payload as JSON (`ojd profile list --json` or similar).
  If one does, the `$defs` entry of that command path in `Resources/Schemas/v1beta1/cli-output.schema.json` gains `packageProfiles`, and P2 owns the schema in wave 2.
- Watcher: `startProfileWatcher` (`ApplicationServiceRuntime.swift:152-174`, unverified) also watches `ModPackageStore.directory(besides: ...)`, or the library's `packagesDirectory`, with `FileChangeWatcher` (`Runtime/FileChangeWatcher.swift`), on the same debounce, and calls the existing reload. `ModPackageStore.swift:76-78` documents that the store folder changes on install, replace, and remove.
  The missing-folder case follows whatever `FileChangeWatcher` already does for a missing `Profiles/`.
- Same volume: `install` stages in `Packages/.staging.<uuid>` (`ModPackageStore.swift:93`), a child of the store, so `replaceItemAt` (`:114`) always swaps on one volume. `list()` skips hidden entries (`:46`), so the staging folder is never served.
  No defect.

### C: `ojd mod` (REQ-6 to REQ-10)

- Files: `Sources/OpenJoystickDriverCLI/Commands/Mod/ModCommand.swift` (group), `ModFileCommands.swift` (validate, install, list, remove), and `ModReport.swift` (output values).
  These follow `Commands/Record/RecordCommand.swift`, `RecordFileCommands.swift`, and `RecordReport.swift`.
  Register the group where `RecordCommand` is registered (P3 finds it with `grep -rn RecordCommand.self Sources/OpenJoystickDriverCLI`).
- Kinds: P3 reads `CLI+OutputKind.swift` and copies the pattern that `record validate|install|list|remove` uses.
  The default proposal is `ModPackageValidation` (validate), `ModPackage` (install, with `dryRun`), `ModPackageList` (list), and `Status` (remove), because the brief says that a list kind is `<Kind>List` and that an action with no object prints `Status`.
  If `record` uses another shape, P3 follows `record` and records the difference in the package report.
- Schema: one `$defs` entry each, `modValidate`, `modInstall`, `modList`, and `modRemove`, in `cli-output.schema.json`, plus the test that `CLIOutputSchemaTests` already runs on each kind.
- Writes: `install` and `remove` call `ModPackageStore` directly, as the record commands write the user's `Controllers/` folder (`cli.record.discussion`: "Only 'ojd record draft' needs the service").
  The service picks up the change through the B3 watcher.
  The service is not needed.
- `--dry-run`: `install --dry-run` runs `ModPackageStore.validate` and refuses an existing name without `--force`, as `install` does, and writes nothing. `remove --dry-run` checks that the entry exists, with the same name rules as `remove` (`ModPackageStore.swift:135-142`), and writes nothing. `--force` maps to `install(_, replace: true)`.
  It never skips `validate`, so `requires` and clashes still refuse (REQ-7).
- Errors: a `ModPackageError` prints its `code` (E4001-E4007) and `detail`, through the error path that `record` uses for its E-codes, and exits with the exit code that `wiki/Command-Line.md` gives for a refused input (P3 reads it).
  No new code is needed.
  If one is needed, P3 adds it to `Resources/ErrorCodes.json` and `ErrorCode.swift` and runs `./Scripts/ojd errors regenerate --write`.
- Strings: `cli.mod.*` keys go into `Localizable.template.strings`, `en-US`, `C`, and every other catalog (English placeholder text marked for P7).
  Help text is in the `CommandConfiguration` with localized keys (`CONTRIBUTING.md:71`).

### E3029 presentation (REQ-11)

- App: `Sources/OpenJoystickDriverPresentation/Runtime/RuntimePresentationErrors.swift` maps remapping RPC codes to keys and falls back to `error.generic` (`:66-69`); no case renders `error.<code>` generically, and `cf59d456` did not touch this file.
  Add a case `.packageProfileReadOnly: OJDLocalized.string("error.E3029")`; the key exists (`en-US.lproj/Localizable.strings:1600`).
- CLI: `cf59d456` changed only `ControllerCalibrateCommand.failure` (`ControllerRemappingCommands.swift:103-126`), which profile commands never call.
  Profile commands go through `ServiceConnection` (`Commands/Profile/ProfileCommand.swift:81,228,283,323,377`, `ProfileFileCommands.swift:50,287,298`), and `Root/ServiceConnection.swift:69-70` prints the service's English `rejection.localizedDescription`.
  Add a `.packageProfileReadOnly` case beside `.duplicateName` (`:61-64`) that prints the localized `error.E3029` text with the code.
- Tests: one new test for each side.

### D: sample package and docs (REQ-13, REQ-14, REQ-15)

- `docs/sdk/sample/` (new): `mod.json` (`$schema` from `ModPackageManifest.knownSchemaIDs`, `name: "ojd-sample"`, `requires: {"minimum": "0.6.0-alpha.1", "below": "0.7.0"}`), `Controllers/<vvvv>-<pppp>.json`, `Profiles/<name>.json`, and `Personas/<vvvv>-<pppp>.json`.
  The file-name patterns are in `ModPackageManifest.swift:104-107`.
  The record's identity must not clash with a bundled or user record in the test fixture.
- `record test` fixture: P5 reads `Tests/OpenJoystickDriverCLITests/Commands/RecordTestCommandTests.swift` to find the capture and expected-state format, and puts `capture` and `expected` files for the sample record in a test fixture folder, not in the package (a package refuses unlisted entries, `ModPackageStore+Validation.swift:151-159`).
- Test: `Tests/OpenJoystickDriverCLITests/Commands/SampleModPackageTests.swift` runs `ojd mod validate docs/sdk/sample --json` and `ojd record test` on the sample record through the existing `CLIRun` support, with a temporary store directory.
- Docs: `wiki/Writing-Controller-Mods.md` (new).
  Its first statement is that the USB extension's product list is Apple-signed and cannot be extended.
  Add the page to `wiki/Home.md` and `wiki/_Sidebar.md` (`wiki/AGENTS.md` needs both), and update `Command-Line.md`, `Command-Reference.md`, and `Controller-Records.md`.
  One line per paragraph, no source paths.
- `CHANGELOG.md`: one line each for mod packages and `ojd mod`, E3029, and E4001-E4007.
  Maintainer decision D3: P6 renames `## [Unreleased]` to `## [0.6.0-alpha.1] - <date>` in the release commit, with the date of the day the maintainer approves that commit (`date -u +%F`), and adds the compare link if the file has link references.
  No package invents another date.

### l10n review (REQ-12)

P7 reviews `error.E3029`, `error.E4001`-`error.E4007`, `cli.explain.area.mod`, and every `cli.mod.*` key in the 20 non-English catalogs against `LOCALIZATION.md` "Meaning" and "Punctuation".
It keeps keys and placeholders, keeps `mod.json`, `ojd mod list`, and `--force` in English, and uses one term per concept (package, profile). `git diff` shows that the B1 renumbering moved the old E4007 text to E3029 in each locale; P7 checks that the new E4007 is the old E4008 text in each locale.

### Full check (REQ-16)

P8 runs each command of `CLAUDE.md` "Checks" and `./Scripts/ojd test parsers-macos14` with:
`export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0; unset TOOLCHAINS; export PATH=$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH`.
It is unverified that `./Scripts/ojd check schemas` fails when the 6.3.3 user toolchain is first on `PATH`.
P8 records which toolchain it ran with, and does not change a check to make it pass.

### Commit points

The maintainer approves each commit.
Natural boundaries: (1) B1+B2 after P1; (2) B3 after P2; (3) C after P3; (4) E3029 after P4; (5) D after P5 and P6; (6) l10n after P7.
P8 only checks.
Trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

### Decisions

- D1 (maintainer): skip and list an out-of-range package in all three layers; see "`requires` at runtime".
- D2: `record` uses `ControllerRecord`, `ControllerRecordList`, `RecordValidation`, and `Status` (`CLI+OutputKind.swift:60-66`), so `ojd mod` uses `ModPackage`, `ModPackageList`, `ModPackageValidation`, and `Status`.
- D3 (maintainer): the heading gets the date of the approved release commit.

### Ownership toggle (REQ-18..22)

- Storage (decision D4, proposed): the choice is the `ownership` field of the user's record `Controllers/<vvvv>-<pppp>.json`.
  A missing file becomes a new `patch` record with only the identity and `ownership` when the model has a bundled or package record; a model with no record is refused with E2023 and a pointer to `ojd record draft` (maintainer decision, 2026-10-14), because a `patch` cannot apply without a base (`ControllerRecordSet.swift:320-325`); an existing user file keeps all its other keys, and only `ownership` is set or replaced.
  Reason: `DeviceCatalog.takesOwnership(of:)` (`DeviceCatalog.swift:42-44`) already reads the merged record, `ControllerRecordWatcher` (`ControllerRecordWatcher.swift:47-58`) already reloads `Controllers/`, and `controller show` already prints the record layer and file (`ControllerReport.swift:87-96`), so a separate store would add a second precedence source to the same field.
  `ojd record install` copies the user's bytes whole with `data.write(to:options: .atomic)` (`RecordFileCommands.swift:165-177,207-213`) and never merges; the toggle needs one new merge helper in `OpenJoystickDriverKit`, beside `ControllerRecordSet`, that decodes the file as a JSON object, sets `ownership`, validates the result with `ControllerRecordSet.validate` (`RecordFileCommands.swift:43-44`), and writes it atomically.
  An invalid existing user file refuses the toggle with its problem text and is not rewritten.
- Re-apply without replugging (REQ-21), a defect found while planning: `nativePassThrough` is computed once in `handleDeviceAdded` (`HIDDeviceStream+DeviceLifecycle.swift:49-55`) and stored on the connection's physical device (`PhysicalInterfaceSignature.swift:247`, a `let`).
  `readmitHIDConnections` (`DeviceManager+Lifecycle.swift:96-124`) re-admits with the stored value (`:118`), and the seize happens only in `handleDeviceAdded` (`:73-75`).
  So a changed `ownership` does not seize or release a connected controller until it is plugged in again, and `wiki/Controller-Records.md:45` overstates this (unverified on hardware).
  Fix: `HIDDeviceStream` gains a main-actor `reevaluateOwnership(of identities:)` that, for each device whose VID:PID is in the set and whose recomputed `nativePassThrough` differs, removes every tracked interface of that device first and then adds them all again, so no sibling keeps the old native flag (`HIDDeviceStream+DeviceLifecycle.swift:73`); the re-evaluated connections are left out of `readmitHIDConnections` (`DeviceManager+Lifecycle.swift:96-123`) so a device is not admitted twice.
  `HIDAccessBackend` (`Session.swift:69-101`) gets the requirement with a default no-op, so the test fakes in `Tests/OpenJoystickDriverKitTests/Device/Support/` need no change, and `BluetoothLECompositeHIDBackend` (`Switch2BluetoothLERouting.swift:6`) forwards it; `reloadControllerRecords` (`DeviceManager+Lifecycle.swift:78-92`) calls it for the changed identities.
  The removed/added events then flow through the normal detach and attach paths.
- Dispatch (REQ-20): no gate change. `observedInputDemand` is set only when `macOSOwnedOutput` is set (`DevicePipeline.swift:158-159`), which happens only for `nativePassThrough` (`DeviceManager+HIDAdmission.swift:198-199`), so an OJD-owned controller has a nil demand and passes `DevicePipeline+InputEvents.swift:57`.
  A seized controller reports `exclusiveHID` (`DeviceManager+DiscoveryModels.swift:63-67`) and is `eligible` (`ControllerExposureDecision.swift:62-117`); a failed seize reports `nativeHIDVisible` and is suppressed (`:84-91`), and `controller show` shows that.
  A test pins that a model GameController supports, with `ownership: ojd` and a passthrough profile, dispatches each changed report.
- `controller show`: `ControllerShowReport.Ownership` (`ControllerReport.swift:6-11`) gains `choice` (`native`|`virtual`) and `choiceSource` (`bundled`|`package`|`user`|`default`), from the effective record's `ownership` and `fieldLayers["ownership"]` (`ControllerRecordSet.swift:36`), not the record's top `layer`; the human output adds a new row `cli.controller.show.ownershipChoice`, because `ControllerCommandTests.swift:236-242` pins `cli.controller.show.ownership`.
- Refusal (REQ-22): a raw-USB record (`DeviceCatalog.swift:22`, `usesRawUSB`) or a model that GameController does not support refuses.
  The CLI checks "supported natively" from the service's `physicalOwnership == nativeGamepad` or the record's ownership being `ojd` (a seized native model), so the controller must be connected.
  Error code (decision D5): add one new `E2023` "ownership toggle not supported for this controller" to `Resources/ErrorCodes.json` (last controller code is `E2022`, `ErrorCodes.json:206`) and run `./Scripts/ojd errors regenerate --write`; the detail names the reason (raw-USB family or not native).
- Output: `ojd controller ownership` returns an object, so its kind is `ControllerOwnership` (`CLI+OutputKind.swift` rules), with `{controller, identity, ownership, previous, file, created, dryRun}`, and `$defs.controllerOwnership` in `cli-output.schema.json`; the `controllerShow` entry gains the two new fields.
- App (REQ-19): the app changes per-model choices through service RPCs, for example `setVirtualHIDProfileOverride` (`ApplicationServiceClient+Requests.swift:164`) and `setSetting` (`:305`).
  Add `setControllerOwnership(identity:ownership:)` beside them (method, payload, client call, service handler, and route in `LocalRPCBridge.swift:146`), handled with the same Kit helper; the record watcher then applies it. `LocalRPCBridgeTests.swift:9-34` pins the method set, and the maintainer approved adding this one name (2026-10-14).
  The picker goes beside `VirtualHIDProfileOverrideView` in `Controllers/Inventory/ControllerDetailView+Facts.swift:30`, through `ApplicationServiceGateway.swift:91`, `ApplicationServiceClientGateway+Requests.swift`, and `RuntimeViewModel+ControllerActions.swift`; the test stub `GatewayStub.swift:31` gains the one new method.
- The CLI writes the file directly, as `ojd record install` does, and needs no service for the write; it needs the service only to resolve `CONTROLLER` and to check native support.

### Stick stutter (REQ-23)

Symptom: games that read through GameController, CrossOver, and browsers see stick delay, holds, and snaps; the OJD preview (pipeline state) is smooth; buttons and triggers are fine; a Steam binding needs a long press.
Hypotheses, most likely first (all from reading, none measured):

1. Dedup of identical reports (`InputReportState.swift:49-55`) and dispatch-on-change (`DevicePipeline+InputEvents.swift:61`): when a stick rests at a value, no report is sent, and some readers infer hold or need repeats. Distinguish: count reports per second at the `IOHIDUserDevice` with a held stick vs. a moving stick.
1. Upstream backlog (review finding, most likely): `deliver` awaits `.value()` (`UserSpaceOutputDispatcher+Delivery.swift:42-55`) and `dispatch` awaits `deliver` (`AutomaticUserSpaceOutputDispatcher.swift:188`), so the sender holds at most one report per pipeline and an overflow closes the entry (`:57-63`) rather than dropping silently; but the HID event streams are unbounded (`HIDDeviceStream+EventStreamAndReports.swift:12`, `Switch2BluetoothLERouting.swift:20`), so input reports queue behind each awaited send, and the virtual stick shows stale values, then snaps. Distinguish: a unit test with a slow fake send that counts stale reports delivered before the newest.
1. Per-event async hops (`UserSpaceOutputDispatcher+Delivery.swift:21-27`) reorder or delay reports. Distinguish: timestamps at pipeline dispatch and at `IOHIDUserDeviceHandleReport`; check order and latency.
1. Swallowed send errors (`AutomaticUserSpaceOutputDispatcher.swift:188`) and the 2 s deadline hide stalls. Distinguish: count errors and deadline hits.
1. `ForegroundInputMask` hides a stick until neutral after focus changes (`ForegroundInputMask.swift`, `DevicePipeline+InputEvents.swift:49-53`). Distinguish: does the stutter follow app focus changes.

Buttons are fine and sticks are not, which fits 2 (a backlog of stale values hurts a continuous value and only delays a button edge) more than 1 or 3.
P9 (`agent: debugger`) measures with unit tests, finds the cause, makes the smallest fix (for 2: coalesce input reports to the latest state per device before the awaited send, keeping every button edge), adds a regression test, and stops to report when the cause needs hardware timing.

### Issue #18 (REQ-24)

Facts: `045E:02D1` with the XboxUSBDevice extension active is not in `controller list` on Intel macOS 15.8.1 and Apple Silicon macOS 26, builds 0.5.0-beta.4 and beta.5 (thread in the brief; user data).
Hypotheses, most likely first:

1. The host profiles lack `com.apple.developer.driverkit.userclient-access` (`Host.entitlements:16-20`), and `Scripts/Signing/configure.py:261-291` and `Scripts/Build/driverkit.sh:178-229` then omit the extension, so the shipped host cannot open the extension's user client and the controller never binds. Distinguish: `codesign -d --entitlements -` on a tester build and the service log's user-client open result.
1. The extension matches 02D1 but the USB detection path (`DeviceManager+USBDetection.swift`) does not bind it to `xbox.gip` (record or product list). Distinguish: `ojd record show 045e:02d1`, `ioreg -l -w0 -r -c IOUSBHostDevice` for the extension's match, and the service log on attach.
1. The first-generation 02D1 needs a different GIP startup than later models. Distinguish: a capture with `ojd controller capture` after binding.

P10 (`agent: debugger`) reads the thread, tests 2 offline (records, product list, detection path), and writes evidence to `docs/testing/xbox-one-02d1.md`. If the cause is 1 or needs hardware, it stops and reports; P6 adds the `wiki/Known-Issues.md` line when the cause is outside the code.

### Signing doctor (REQ-25)

`just signing-doctor` runs `./Scripts/ojd signing doctor` (`justfile:176-177`).
P13 first checks that the regenerated host profiles hold `com.apple.developer.driverkit.userclient-access`, and stops with a report when they do not; it changes no file.

### Host profile grant check (REQ-26)

The installed host profiles grant `userclient-access` to `com.openjoystickdriver.XboxUSBDevice` and `com.openjoystickdriver.VirtualHIDDevice`.
`configure.py:291-293`, `doctor.py:209`, and `driverkit.sh:201` require the list to be exactly XboxUSBDevice, so `signing configure` refuses the profiles.
P14 (wave 1) changes those three checks to "a list of strings that includes XboxUSBDevice", keeps refusing a wildcard, a non-string item, and `allow-any-userclient-access`, and keeps the exact check of the authored `Host.entitlements` (`driverkit.sh:145-171`).
P13 moves to wave 2 behind P14.

### Xbox One 02D1 DEXT transport (REQ-24)

P10 (`docs/testing/xbox-one-02d1.md`, source evidence, no hardware run) found the defect in the USB transport adapter.
SwifterKit 0.3.0 writes `idProductArray` for the extension's seven products, and the DEXT service carries no scalar `idProduct` and no `locationID`.
`USBDriverKitTransportProvider.device(_:)` therefore returns nil, and `selectDevices` keeps the seven products off direct IOUSBHost, so `045E:02D1` reaches no route.
P15 (wave 2, after P10) reads the identity, the `locationID`, and the name strings from the parent `IOUSBHostDevice` of each DEXT service, and keeps the DEXT service ID for the open.
H1 remains: a missing `userclient-access` grant can still fail the open.

### Waves after the added scope

Wave 1: P1, P4, P9, P10, P14.
Wave 2: P13, P15.
Wave 4: P5, P11.
Wave 5: P6, P7, P12.
Wave 6: P8.
P11 owns the catalogs, the CLI schema, and the error files in wave 4; P12 owns only Presentation files and tests in wave 5, because P7 owns the catalogs there, so P11 adds the app's strings too.

### Decisions (added scope)

- Maintainer decisions (2026-10-14): ownership toggle in the CLI and the app; the `VirtualHIDDevice` extension is not restored; stutter and #18 are debugger packages; the maintainer confirms on hardware.
- D4 (decided): the ownership choice lives in the user record's `ownership` field, merged into an existing user file, because the catalog, the record watcher, and `controller show` already read that field.
- D5 (decided): one new code `E2023` for a refused toggle, the next free controller code.
- D6 (decided): the CLI writes the record directly, as `record install` does; the app goes through a new `setControllerOwnership` RPC, as it does for `setVirtualHIDProfileOverride`.
- Signing (2026-10-14): the regenerated `OpenJoystickDriver_XboxUSBDevice*.provisionprofile` files carry `userclient-access`, but the host profiles `OpenJoystickDriver*.provisionprofile` do not.
  Apple's entitlement page says to add it "to your app that opens the IOUserClient", and only `Host.entitlements:17` requests it, so the grant belongs on the host App ID `com.openjoystickdriver`.
  The maintainer regenerated and installed the host profiles on 2026-10-14; they grant XboxUSBDevice and VirtualHIDDevice.
- D7 (decided, 2026-10-14): the host profile check accepts a list that includes XboxUSBDevice instead of exactly that list (P14).

## Risks / Trade-offs

- [H1: a missing or refused `userclient-access` grant can still fail `client.open` on the DEXT route] → P15 keeps the DEXT service ID for the open; the maintainer confirms `045E:02D1` on hardware.
- [The stick stutter fix (P9) is shown by unit tests, not hardware timing] → The maintainer runs the hardware check listed in `tasks.md`.
- [Items marked "unverified" were not read while the design was written] → The task group that touches each one reads it first and stops to report when it differs.
