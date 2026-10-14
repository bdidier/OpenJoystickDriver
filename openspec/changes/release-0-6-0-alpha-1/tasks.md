# Tasks

Converted on 2026-10-14 from the dotclaude spec `.dotclaude/spec/changes/0.6.0-alpha.1/` (15 packages, P1 to P15).
Each `## n. Pk` group is one dotclaude package, ordered by wave.
Its header bullets keep the package metadata (status, wave, deps, satisfies, agent, branch, owned files, verify command), and its last three tasks track verify, review, and merge.
A step box is checked when the package reached `verified`; the review box when `events.jsonl` records `approved`; the merge box when the package is `done`.
Each group ends with its state history from `events.jsonl`.

Progress at conversion: 8 of 15 packages done (P1, P2, P4, P9, P10, P13, P14, P15); P3 verified and approved by a reviewer agent, verdict not recorded, not merged; P5, P6, P7, P8, P11, P12 planned.
Branch `feat/0.6.0-alpha.1` head `9608bebc` (merge of P15), not pushed.

Change history: draft 2026-10-13T22:59:44Z; specified and planned 2026-10-13T23:14:44Z; implementing 2026-10-14T01:01:50Z.

## Working agreements

Constraints of the user, word for word from the dotclaude handoff `handoff-20261014T030825Z.md` (typos kept, `[sic]` marks them):

- "You do it.
  If you need to be out of sandbox, you be out of sandbox.
  All user wants you to do is work towards 0/15 as much as non-hardware requires. what requires hardware to test is implemented, but verification left to last for user."
- "You are allowed to commit.
  Just do not modify the main branch.
  This branch is all yours."
- "Your decision is to automate this process.
  You use your worktrees, and you continue your work.
  You can push to this branch, you can commit to it--you work on it."
- "ou [sic] can't just ask a question and not pause to wait for an answer.
  Choose your reocmmendation [sic] always.
  But think forward."
- "you can kill the process outside sandobx [sic] when you must."
- "Keep going.
  You just keep going until 0/15 tasks are fulfilled.
  You can add them by going out of sandbox. it's a runtime plugin issue user is fixing in another session. hERE, is a workaround."

"This branch" is `feat/0.6.0-alpha.1`. Do not touch `main`.

Harness notes from the handoff:

- Run Swift checks from the main session with the sandbox disabled, not from a subagent.
- Each review verdict must come from a fresh reviewer agent; the main session records only its verdict.
- Edits outside a group's "Owns" list were refused until the list was updated; update the list first.
- Every `verify` has `PATH=...:$PATH` without quotes; when `PATH` holds an entry with a space, run `export PATH="$(echo "$PATH" | tr ':' '\n' | grep -v ' ' | paste -sd: -)"` first.
- `.build/schema-validator/bin/python` does not exist in the main checkout.

## Open items

- P3 reviewer findings, none blocking:
  - Should-fix (inherited from `record install`, `RecordFileCommands.swift:46`): `ojd mod install BAD --json` prints a validation body under kind `ModPackage`, which fails the `modInstall` schema (`ModReport.swift:66`). Left unchanged so `mod` and `record` behave the same; `record` is outside P3.
  - Nit: install reports the path from the source folder's manifest, not from the `ModPackage` that `store.install` returns (`ModFileCommands.swift:94-110`).
  - Nit: the ja-JP `cli.mod.install.dry_run` and `cli.mod.remove.dry_run` read "will" instead of "would"; for P7.
- P9 reviewer nits: a suspend during `await retireOutputAfterLivenessLoss()` can let held input replay after resume (`DevicePipeline+InputEvents.swift:25`; fix: re-check `sessionState == .active` after the await); the new `visible.touch` comparison (`:90`) has no test.
- P11 reviewer findings, none blocking:
  - Should-fix: toggling the ownership of a suspended controller ends its suspension. `reevaluateOwnership` sends a removed event, and `tearDownHIDDevice` clears `suspendedControllerIdentities` (`DeviceManager+HIDTeardown.swift:61`), although the `reloadControllerRecords` comment says the suspension is kept. The fix belongs in `DeviceManager+HIDTeardown.swift`, outside P11's Owns.
  - Should-fix, checked and not a defect: `previous` in `ControllerOwnershipRequests.swift` reads `records.records`, which already holds package records (`ControllerRecordSet.swift:234`).
  - Nit: concurrent toggles from the CLI and the app are last-writer-wins; each write is atomic.
- P11 decisions and follow-ups:
  - A user patch applies over an installed package record when no bundled record exists; if the package is removed, the patch is listed as a problem and skipped (maintainer decision, 2026-10-14). P6 should say so in `wiki/Controller-Records.md`.
  - `CLIRun.swift` joined P11's Owns for one sample-operand case.
  - Assumptions: `reevaluateOwnership` runs from `readmitHIDConnections` through `reloadControllerRecords` and the USB poll path (`DeviceManager+USBDetection.swift:174`); CLI JSON says `native`/`virtual`; the RPC uses `macos`/`ojd` with failure codes that P12 maps to E2023; the RPC counts a model whose record already says `ojd` as native; the writer's `noRecord` maps to E2023 in the CLI.
  - The app keys `controllers.ownership.*` stay unused until P12; P7 reviews the new ownership translations.
  - Follow-up: `ojd record install` and `record validate` (`RecordFileCommands.swift:44`) still validate a patch without a package base.
  - P13 has an empty "Owns" list; it was run without an agent because it changes no file.
  - Whether P15 needs an update of `docs/testing/xbox-one-02d1.md` "Result"; P6 or the maintainer owns that page.
  - What to do with the left-over worktrees `.claude/worktrees/agent-a6ec4211cf41e0912` and `agent-adfb7ffcf65ee534f` (on `origin/main`, with deletions under `.agents/skills/` that are not from this change).
- P5 reviewer nits: the sample-package test fixture covers 2 of 8 buttons and no negative axes; the `#filePath` path chains repeat.
- P6: approved by the fifth reviewer. After P12, `8fd7bdba` named the app picker in the CHANGELOG and `Controller-Records.md` and ticked 12.5; a sixth reviewer approved, and `05199978` took its should-fix (the picker shows for any record that gives a model to OJD). The maintainer chose to merge P6 at the end (2026-10-14); their uncommitted `wiki/Controller-Records.md` edit was saved as a patch, the file restored, P6 merged at `53acb754`, and the patch applied again. P6 found that OJD does not report a package profile that it ignores because of a clash, and the wiki says so.
- `docs/testing/xbox-one-02d1.md` "Result" still says the fix is outside this package; no group owns the page.
- P7 reviewer nits, not taken: `error.E2023` translates "native and virtual" as prose; hi-IN ownership `dry_run` could use the passive; zh-TW/zh-HK 發佈 vs 發布; ar-SA مثبتة without shadda. Rejected: zh-TW/zh-HK 虛擬遊戲控制器 is the files' own term (33 uses); the vi-VN `cli.profile.*.examples` "hồ sơ" is outside P7's keys.
- The left-over worktree `.claude/worktrees/agent-a7460c9a8d6f138cc` is also undecided.
- P12 reviewer findings, none blocking:
  - Should-fix: after a toggle the app refreshes the inventory once, right after the RPC returns, while the record watcher re-admits the controller later; the picker can show the old value until the next refresh. The maintainer's manual check confirms whether it settles; the fix would be a short re-poll.
  - Should-fix: every `ControllerOwnershipFailure` shows the `error.E2023` text, which names raw USB and native support; `noRecord`, `invalidRecord`, and `persistenceFailed` append the service's detail instead of a text of their own.
  - Accepted: `GatewayStub` gained a call recorder and a failure knob beside the method, mirroring the override stub; the protocol default of `setControllerOwnership` returns `.noRecord` for test conformers, like the suspend/resume defaults.
- P12 decision: its Owns gained three Kit files and a Kit test (2026-10-14), so the device payload carries `recordOwnership`, the effective layered ownership, decoded as `.macOS` when absent.
- P8 report (2026-10-14, commit `5b43e065`, worktree `.claude/worktrees/spec-P8`):
  - Toolchain: `/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift`, `Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)`, with the environment of `design.md` "Full check". The Python checks used the main checkout's `.build/schema-validator/bin/python`, because the worktree has no `.build`.
  - Each command of the `CLAUDE.md` Checks list exited 0, run one at a time, and so did `./Scripts/ojd test parsers-macos14`: `swift test` ran 2555 tests in 352 suites, the repository unittest ran 180 tests (1 skipped), markdownlint linted 110 files, swiftlint linted 1083 files.
  - `./Scripts/ojd check schemas` exits 0 with the Xcode toolchain and exits 1 with the user-installed 6.3.3 toolchain (`~/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain`, through swiftly) first on `PATH`: compiling `Package.swift` against the CommandLineTools SDK fails with `unknown argument: '-target-arch-variant'`.
  - The `verify` command exits 255: `just check` runs `./Scripts/ojd check tools`, which is not in the Checks list, and xmake picks `/Applications/Xcode-27.0.0.app` (SDK 27.0) instead of `DEVELOPER_DIR`; compiling `Tools/SDLGamepadProbe/main.m` fails with `/opt/homebrew/include/SDL3/SDL_platform_defines.h:146:10: fatal error: 'AvailabilityMacros.h' file not found`. The same command fails the same way on `main`, so no package of this change owns it (owner: environment); it looks like the machine's Xcode selection for xmake, not tested with xmake forced to Xcode 26.6. The steps of `just check` after it passed when run alone: `check driverkit`, `test parsers-macos14`, and `swift test --no-parallel` (2555 tests). 15.5 stays open until the maintainer accepts this or fixes the xmake Xcode selection.

## 1. P1: B2 review fixes and requires at runtime

- dotclaude status: `done`
- Wave: 1; deps: none; satisfies: REQ-1, REQ-2, REQ-3, REQ-17; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P1`; worktree: `.claude/worktrees/spec-P1`
- Owns: `Sources/OpenJoystickDriverService/Remapping/Profiles/RemappingProfileLibrary+Packages.swift`, `Sources/OpenJoystickDriverKit/Packages/ModPackageStore.swift`, `Sources/OpenJoystickDriverKit/Packages/ModPackageStore+Validation.swift`, `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet+Packages.swift`, `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet.swift`, `Sources/OpenJoystickDriverService/Remapping/Profiles/RemappingProfileLibrary.swift`, `Sources/OpenJoystickDriverKit/Output/Profiles/VirtualHIDProfileOverrideStore.swift`, `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+Packages.swift`, `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+PackageClashes.swift`, `Tests/OpenJoystickDriverKitTests/Packages/ModPackageRequiresAtRuntimeTests.swift`
- Verify: `env -u TOOLCHAINS DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0 PATH=/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter 'ProfileLibraryTests|ModPackage|ControllerRecordSet|VirtualHIDProfileOverride|RemappingRequestCoordinatorTests'`

Goal:

The B2 code holds REQ-1 to REQ-3 with tests: unreadable or invalid package profiles are logged and skipped, and the clash rules have tests for name-only shadowing and package order.
A package whose `requires` excludes the running version is skipped by the record, persona, and profile layers and listed with its E4002 reason (REQ-17).

Context:

- `design.md` sections "B2 review" and "`requires` at runtime".
- `Sources/OpenJoystickDriverService/Remapping/Profiles/RemappingProfileLibrary+Packages.swift:1-91`.
- `RemappingProfileLibrary+Persistence.swift:8-81,130-170`, `+Operations.swift:43-145`, `+Recovery.swift:59-127`.
- `Sources/OpenJoystickDriverKit/Packages/ModPackageStore.swift:1-67`, `ModPackageStore+Validation.swift:40-60`, `ModPackageManifest.swift:146-163` (`admits`).
- `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet+Packages.swift:20-74`.
- `Sources/OpenJoystickDriverKit/Output/Profiles/VirtualHIDProfileOverrideStore.swift:25-40,79-105,210-235`.
- `RemappingProfileFileStore.load(from:)` (find with `grep -rn "RemappingProfileFileStore" Sources/OpenJoystickDriverKit`).
- `RemappingProfileLibrary.swift:68-73` and `ControllerRecordSet.swift:156-162` (same `<AppSupport>/OpenJoystickDriver` parent).
- `Tests/OpenJoystickDriverServiceTests/Remapping/Profiles/ProfileLibraryTests+Packages.swift` and `Tests/OpenJoystickDriverKitTests/Packages/ModPackageStoreTests.swift` for fixtures.

- [x] 1.1 In `loadPackageProfiles`, replace the silent `continue` for an unreadable or undecodable file with one `fputs("[Profiles] ...\n", stderr)` line that names the package and the file, in the form of `discardLegacyLibrary` (`+Recovery.swift:67-76`).
- [x] 1.2 Read `RemappingProfileFileStore.load(from:)`.
  If it does not run `profile.validate()`, call `validate()` in `loadPackageProfiles` and log and skip an invalid profile with the same line.
- [x] 1.3 In `ModPackageStore.list()`, set `problem` to the E4002 text of a package whose `requires` does not admit `runningVersion`, and keep its `manifest`. Move the E4002 message building in `ModPackageStore+Validation.swift:49-56` into one helper that both use. When `runningVersion` does not parse as `SemanticVersion`, `list()` admits every package (development build); `validate` keeps refusing (`:43-48`). In `validate`, count another package's claims (`:63-66`) only when its `problem` is nil.
- [x] 1.4 Make each layer skip a package whose `problem` is not nil: `ControllerRecordSet+Packages.swift` lists it as a file with the problem; `VirtualHIDProfileOverrideStore` adds one `VirtualPersonaFile` with the problem for its `mod.json`; `loadPackageProfiles` logs and skips it. Give `ControllerRecordSet.packageRecords(in:)` (and its caller at `ControllerRecordSet.swift:212` if needed), `VirtualHIDProfileOverrideStore.init`, and `RemappingProfileLibrary` a `runningVersion: String? = nil` that they pass to `ModPackageStore(directory:runningVersion:)`; `nil` keeps the default, so no existing caller or fixture changes.
- [x] 1.5 Add tests in new files only: in `ProfileLibraryTests+PackageClashes.swift`, a user profile that shadows a package profile by name only; two packages with the same profile name, where the first by package name wins; `delete` of a shadowing user profile leaves the package file; `replace` and `restore` leave every file under `Packages/` byte-equal; a skipped unreadable package profile does not stop the others; `packagesDirectory == ModPackageStore.rootDirectory` for the default directory; an out-of-range package serves no profile.
  In `ModPackageRequiresAtRuntimeTests.swift`, with a running version of `9.0.0`: `list()` gives the E4002 problem and keeps the manifest; with `unknown` it admits the package; the record layer and the persona layer skip and list an out-of-range package; an out-of-range package does not block the install of another package that holds the same identity.
- [x] 1.6 Watch each new test fail before its fix, and say so in the report.
- [x] 1.7 Verify: the `verify` command above exits 0. Acceptance: The `verify` command passes, with the new tests. The report says whether design defect 2 is real.
- [x] 1.8 Review: a fresh reviewer agent approves the diff
- [x] 1.9 Merge `spec/0.6.0-alpha.1-P1` into `feat/0.6.0-alpha.1`

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only. Existing fixtures use `minimum 0.6.0` and run with an unparsable version; if one of them fails, stop and report instead of editing it.
- Do not add a new error code or a new localized string; E4002 exists.
- Doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py`.
- Change only the files in `owns`; report a needed change elsewhere instead of making it.

History (from `events.jsonl`):

- 2026-10-14T01:01:50.803Z `doing` at `762a41ee`
- 2026-10-14T01:16:29.869Z `verified` at `af09b89a`, verify exit 0
- 2026-10-14T02:12:58.757Z `doing`, verdict `reject`; finding: ProfileLibraryTests+PackageClashes.swift:92,136,152 exceed 100 columns and :94:58 lacks trailing comma; swift-format --strict and swiftlint --strict fail; finding: nit: ModPackageRequiresAtRuntimeTests.swift compares problem to a full English sentence; decision: `fix-code`
- 2026-10-14T02:14:27.338Z `verified` at `18a5bb12`, verify exit 0
- 2026-10-14T02:26:45.471Z `approved` at `18a5bb12`, verdict `approve`
- 2026-10-14T03:05:52.366Z `done` at `18a5bb12`

## 2. P4: E3029 presentation in app and CLI

- dotclaude status: `done`
- Wave: 1; deps: none; satisfies: REQ-11; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P4`; worktree: `.claude/worktrees/spec-P4`
- Owns: `Sources/OpenJoystickDriverPresentation/Runtime/RuntimePresentationErrors.swift`, `Sources/OpenJoystickDriverCLI/Root/ServiceConnection.swift`, `Tests/OpenJoystickDriverPresentationTests/Runtime/RuntimePresentationErrorsTests.swift`, `Tests/OpenJoystickDriverCLITests/Root/ServiceConnectionPackageProfileTests.swift`
- Verify: `env -u TOOLCHAINS DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0 PATH=/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter 'RuntimePresentation|ServiceConnectionPackageProfile'`

Goal:

The app and the CLI show the localized `error.E3029` text for a refused package profile change, not `error.generic` or the English message of the service.

Context:

- `design.md` section "E3029 presentation".
- `Sources/OpenJoystickDriverPresentation/Runtime/RuntimePresentationErrors.swift:35-95`: unmatched remapping codes fall back to `error.generic` (`:66-69`).
- `Sources/OpenJoystickDriverCLI/Root/ServiceConnection.swift:55-75`: `.duplicateName` has its own case (`:61-64`); every other `ApplicationServiceRemappingRPCError` prints `rejection.localizedDescription`, the service's English text (`:69-70`).
- Profile commands reach that path through `ServiceConnection.request` and `withDeadline` (`Commands/Profile/ProfileCommand.swift:81,228,283,323,377`, `ProfileFileCommands.swift:50,287,298`).
- `ApplicationServiceRemappingRPC.swift` (the `packageProfileReadOnly` case, read only); key `error.E3029` in `Sources/OpenJoystickDriverKit/Resources/en-US.lproj/Localizable.strings:1600`.
- Existing tests in `Tests/OpenJoystickDriverPresentationTests/Runtime/RuntimePresentationErrorsTests.swift` and `Tests/OpenJoystickDriverCLITests/Root/` for fixtures.

- [x] 2.1 In `RuntimePresentationErrors.swift`, add a case `.packageProfileReadOnly` that returns `OJDLocalized.string("error.E3029")`, beside the existing remapping cases.
- [x] 2.2 In `ServiceConnection.swift`, add a case for `rejection.code == .packageProfileReadOnly` before the generic case, in the form of `.duplicateName` (`:61-64`), that fails with the localized `error.E3029` text and `rejection.code.errorCode`.
- [x] 2.3 Add a test on each side, in the new or existing test file in `owns`, that E3029 renders the `error.E3029` catalog value (compare to `OJDLocalized.string("error.E3029")`, not to an English literal) and keeps the code E3029.
- [x] 2.4 Watch each new test fail before its fix, and say so in the report.
- [x] 2.5 Verify: the `verify` command above exits 0. Acceptance: The verify command passes. `python3 Scripts/Quality/check_localization_keys.py` passes.
- [x] 2.6 Review: a fresh reviewer agent approves the diff
- [x] 2.7 Merge `spec/0.6.0-alpha.1-P4` into `feat/0.6.0-alpha.1`

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only.
- Do not add a localized key; `error.E3029` exists.
- Doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py` (500 code lines in Sources, 1000 in Tests).
- Change only the files in `owns`; report a needed change elsewhere instead of making it.

History (from `events.jsonl`):

- 2026-10-14T01:01:50.861Z `doing` at `762a41ee`
- 2026-10-14T01:13:19.749Z `doing` at `1178ab9d`, verify exit 126; note: The command left changes outside `.dotclaude/spec`: Sources/OpenJoystickDriverCLI/Root/ServiceConnection.swift, Sources/OpenJoystickDriverPresentation/Runtime/RuntimePresentationErrors.swift, Tests/OpenJoystickDriverCLITests/Root/ServiceConnectionPackageProfileTests.swift, Tests/OpenJoystickDriverPresentationTests/Runtime/RuntimePresentationErrorsTests.swift.
- 2026-10-14T01:14:05.212Z `verified` at `94ded780`, verify exit 0
- 2026-10-14T02:12:58.716Z `approved` at `94ded780`, verdict `approve`
- 2026-10-14T03:05:52.366Z `done` at `94ded780`

## 3. P9: Virtual stick stutter: root cause and fix

- dotclaude status: `done`
- Wave: 1; deps: none; satisfies: REQ-23; agent: `debugger`
- Branch: `spec/0.6.0-alpha.1-P9`; worktree: `.claude/worktrees/spec-P9`
- Owns: `Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/ReportSender.swift`, `Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/InputReportState.swift`, `Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/UserSpaceOutputDispatcher+Delivery.swift`, `Sources/OpenJoystickDriverService/Runtime/OutputDispatch/AutomaticUserSpaceOutputDispatcher.swift`, `Sources/OpenJoystickDriverKit/Device/Pipeline/DevicePipeline+InputEvents.swift`, `Sources/OpenJoystickDriverKit/HID/HIDDeviceStream+EventStreamAndReports.swift`, `Sources/OpenJoystickDriverKit/Bluetooth/Switch2BluetoothLERouting.swift`, `Sources/OpenJoystickDriverKit/Device/Discovery/HID/DeviceManager+HIDDetection.swift`, `Sources/OpenJoystickDriverKit/Device/Discovery/HID/DeviceManager+HIDTeardown.swift`, `Sources/OpenJoystickDriverKit/Device/Pipeline/DevicePipeline.swift`, `Sources/OpenJoystickDriverKit/Device/Pipeline/DevicePipeline+Lifecycle.swift`, `Tests/OpenJoystickDriverKitTests/Output/Backends/UserSpaceOutputDispatcher/StickDeliveryLatencyTests.swift`
- Verify: `env -u TOOLCHAINS DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0 PATH=/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter StickDeliveryLatencyTests`

Goal:

Find why virtual stick changes are held, delayed, or dropped while the OJD preview is smooth, make the smallest fix, and prove it with a test that fails before the fix.

Context:

- `design.md` section "Stick stutter (REQ-23)": five ranked hypotheses and the measurement for each.
- `ReportSender.swift:18-20,152,202` (buffer 64 with `bufferingOldest`, 2 s deadline); note from review: `deliver` awaits `.value()` (`UserSpaceOutputDispatcher+Delivery.swift:42-55`) and `dispatch` awaits `deliver` (`AutomaticUserSpaceOutputDispatcher.swift:188`), so one pipeline holds at most one report in the sender, and an overflow closes the entry (`Delivery.swift:57-63`) rather than dropping silently. The likelier cause is upstream: the HID event streams are unbounded (`HIDDeviceStream+EventStreamAndReports.swift:12`, `Switch2BluetoothLERouting.swift:20`), so input reports queue behind each awaited send and the virtual stick lags, then snaps; `InputReportState.swift:49-55` (dedup); `UserSpaceOutputDispatcher+Delivery.swift:21-27` (async hops); `AutomaticUserSpaceOutputDispatcher.swift:188` (swallowed errors); `DevicePipeline+InputEvents.swift:49-63` and `ForegroundInputMask.swift` (read only).
- `VirtualDeviceFactory.swift:52,110` (`IOHIDUserDevice` create and activate; read only).

- [x] 3.1 Read the files in Context and the existing tests of `ReportSender` and `InputReportState`.
- [x] 3.2 Write the measurement as unit tests in `StickDeliveryLatencyTests.swift`: feed a burst of stick reports faster than a slow fake send, then check how many stale reports are delivered before the newest, that the newest state is delivered within one send time, and that no change is reordered. Test the upstream-queue hypothesis first, then hypotheses 1-4 of the design.
- [x] 3.3 Name the cause that a test shows. Make the smallest fix in an owned file (for an upstream backlog: coalesce input reports to the latest state per device before the awaited send, so a slow send never delivers stale stick values; keep every button edge).
- [x] 3.4 Watch the test fail before the fix and pass after; say so in the report.
- [x] 3.5 If no offline test shows a cause, stop and report the measurement the maintainer must run on hardware (timestamps at dispatch and at `IOHIDUserDeviceHandleReport`, with a game open).
- [x] 3.6 Verify: the `verify` command above exits 0. Acceptance: The verify command passes with the new test, or the report says which hardware measurement is needed and why no offline cause was found.
- [x] 3.7 Review: a fresh reviewer agent approves the diff
- [x] 3.8 Merge `spec/0.6.0-alpha.1-P9` into `feat/0.6.0-alpha.1`

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only.
- Doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py`.
- Change only the files in `owns`; report a needed change elsewhere instead of making it.
- `ForegroundInputMask.swift` is not owned; if the fix needs it, stop and report.
- Do not drop a button press or release while coalescing: a test must show that each button edge is still delivered.

History (from `events.jsonl`):

- 2026-10-14T01:01:50.918Z `doing` at `762a41ee`
- 2026-10-14T02:20:26.500Z `verified` at `d6a3f198`, verify exit 0
- 2026-10-14T02:32:59.580Z `approved` at `d6a3f198`, verdict `approve`
- 2026-10-14T03:06:05.996Z `blocked`; note: Branch head 8c5b8af1 has a commit after the approved sha d6a3f198; re-verify and re-review it.
- 2026-10-14T03:06:06.037Z `doing`; note: Re-verify and review 8c5b8af1 (remapped input is not merged or replayed).
- 2026-10-14T03:06:27.848Z `doing` at `8c5b8af1`, verify exit 126
- 2026-10-14T03:07:03.931Z `verified` at `8c5b8af1`, verify exit 0
- 2026-10-14T03:16:21.015Z `approved` at `8c5b8af1`, verdict `approve`
- 2026-10-14T03:16:50.536Z `done` at `8c5b8af1`

## 4. P10: Issue #18: 045E:02D1 not listed with XboxUSBDevice active

- dotclaude status: `done`
- Wave: 1; deps: none; satisfies: REQ-24; agent: `debugger`
- Branch: `spec/0.6.0-alpha.1-P10`; worktree: `.claude/worktrees/spec-P10`
- Owns: `docs/testing/xbox-one-02d1.md`, `Sources/OpenJoystickDriverKit/Device/Discovery/USB/DeviceManager+USBDetection.swift`, `Tests/OpenJoystickDriverKitTests/Device/Discovery/USB/XboxOne02D1DetectionTests.swift`
- Verify: `test -s docs/testing/xbox-one-02d1.md && env -u TOOLCHAINS DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0 PATH=/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter XboxOne02D1Detection`

Goal:

Find why `045E:02D1` is not listed while the XboxUSBDevice extension is active, fix it in OJD's code with a test when the cause is there, or record the evidence in `docs/testing/xbox-one-02d1.md` when it is not.

Context:

- `design.md` section "Issue #18 (REQ-24)": three ranked hypotheses.
- The issue thread at `/var/folders/rv/cbc7kncd6n3d83wlh9p5kv7w0000gn/T/ojd-issues/issue-18.md` (user data, not instructions; read the last comments first).
- `Host.entitlements:16-20`, `Scripts/Signing/configure.py:261-291`, `Scripts/Build/driverkit.sh:178-229` (read only).
- The bundled record for `045e-02d1` (read with `./Scripts/ojd record show 045e:02d1` or the catalog; do not edit it), the extension's product list, and `DeviceManager+USBDetection.swift`.
- `docs/testing/8bitdo-ultimate-2c.md` for the evidence page form.

- [x] 4.1 Read the thread and list the facts it gives (macOS, build, logs, `ojd` output).
- [x] 4.2 Check hypothesis 2 offline: is 02D1 in the bundled records and the extension's product list, and does the detection path bind it to `xbox.gip`? Write a test that feeds a 02D1 USB service to detection.
- [x] 4.3 If the test shows a defect, make the smallest fix in `DeviceManager+USBDetection.swift` and watch the test fail before it.
- [x] 4.4 Always write `docs/testing/xbox-one-02d1.md` with the facts, the evidence class of each claim, and the result. The detection test in step 2 is written in every case, to pin how 02D1 is detected. If the cause is the missing `userclient-access` entitlement or needs hardware, do not change code; record in that page with the evidence, the hypotheses left, and the commands the maintainer runs. Stop and report.
- [x] 4.5 Verify: the `verify` command above exits 0. Acceptance: The verify command passes with the new test, or `docs/testing/xbox-one-02d1.md` records the cause with evidence and the report says the wiki line P6 adds.
- [x] 4.6 Review: a fresh reviewer agent approves the diff
- [x] 4.7 Merge `spec/0.6.0-alpha.1-P10` into `feat/0.6.0-alpha.1`

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only.
- Doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py`.
- Change only the files in `owns`; report a needed change elsewhere instead of making it.
- If the fix is in another file (a record, the extension, signing scripts), stop and report; records and generated files are not edited here.

History (from `events.jsonl`):

- 2026-10-14T01:01:50.979Z `doing` at `762a41ee`
- 2026-10-14T01:15:11.941Z `verified` at `43942623`, verify exit 0
- 2026-10-14T02:10:22.016Z `approved` at `43942623`, verdict `approve`
- 2026-10-14T03:05:52.365Z `done` at `43942623`

## 5. P14: Accept a host profile whose user-client grant includes XboxUSBDevice

- dotclaude status: `done`
- Wave: 1; deps: none; satisfies: REQ-26; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P14`; worktree: `.claude/worktrees/spec-P14`
- Owns: `Scripts/Signing/configure.py`, `Scripts/Signing/doctor.py`, `Scripts/Build/driverkit.sh`, `Tests/RepositoryScripts/test_signing_profiles.py`, `docs/development/signing.md`, `CONTRIBUTING.md`
- Verify: `ruff format --check Scripts Tests/RepositoryScripts && ruff check Scripts Tests/RepositoryScripts && .build/schema-validator/bin/python -m unittest discover -s Tests/RepositoryScripts -p test_signing_profiles.py && shellcheck --external-sources --source-path=SCRIPTDIR Scripts/Build/driverkit.sh`

Goal:

A host profile whose `com.apple.developer.driverkit.userclient-access` list includes `com.openjoystickdriver.XboxUSBDevice` (the maintainer's regenerated profiles also list `com.openjoystickdriver.VirtualHIDDevice`) passes `signing configure`, `signing doctor`, and the DriverKit build.
The app's own entitlements still claim exactly XboxUSBDevice.

Context:

- Maintainer decision (2026-10-14): relax the host profile check from "exactly" to "includes". `./Scripts/ojd signing configure` failed with `GUI development profile entitlement mismatch for com.apple.developer.driverkit.userclient-access: expected ['com.openjoystickdriver.XboxUSBDevice'], got ['com.openjoystickdriver.XboxUSBDevice', 'com.openjoystickdriver.VirtualHIDDevice']`.
- `Scripts/Signing/configure.py:261-297` (`userclient_ungranted`, `require_host_profile`; the exact compare is `:291-293`).
- `Scripts/Signing/doctor.py:191-212` (`userclient_access_errors`; the exact compare is `:209`), and its uses at `:251-333,381`.
- `Scripts/Build/driverkit.sh:178-211` (`_require_host_access_profile`; the exact compare is `:201`). `driverkit.sh:145-171` checks the authored `Host.entitlements` source exactly; that check stays.
- `Tests/RepositoryScripts/test_signing_profiles.py:63-102`: `:77-83` and `:90,101` assert that `[DEXT, "other"]` is refused, which is the rule this decision changes.
- `docs/development/signing.md:15,38`, `CONTRIBUTING.md:64`.
- Apple: `userclient-access` goes on "your app that opens the IOUserClient", as "an array of bundle IDs of driver extensions" (developer.apple.com, `com.apple.developer.driverkit.userclient-access`).

- [x] 5.1 In `configure.py`, `doctor.py`, and `driverkit.sh:192-207`, accept a host profile value that is a list of strings that includes the DEXT bundle ID.
  Keep refusing a non-list value such as `"*"`, a list with a non-string item, and `allow-any-userclient-access`.
  Keep the release rule: a release profile without the DEXT in the list is fatal.
- [x] 5.2 Leave the authored-source check of `Host.entitlements` (`driverkit.sh:145-171`) exact, so the signed app claims only XboxUSBDevice.
- [x] 5.3 Update the tests: `[DEXT, "other"]` is now accepted by `require_host_profile` and by `userclient_access_errors` (change `:77` and `:90,101` to that rule); `"*"` and a list with a non-string item are still refused.
  Add a test for `[DEXT, "com.openjoystickdriver.VirtualHIDDevice"]`.
  These test changes carry out the maintainer's decision.
- [x] 5.4 Update `signing.md:15,38` and `CONTRIBUTING.md:64`: the host profile's list must include XboxUSBDevice and may name other bundle IDs; `Host.entitlements` claims exactly XboxUSBDevice.
  One line per paragraph.
- [x] 5.5 Run `./Scripts/ojd signing doctor` against the installed profiles and put its output in the report (do not change profiles or `.env` files).
- [x] 5.6 Verify: the `verify` command above exits 0. Acceptance: The verify command passes. `./Scripts/ojd signing doctor` prints `[OK] host profile grants user-client access`, or the report names the remaining failure.
- [x] 5.7 Review: a fresh reviewer agent approves the diff
- [x] 5.8 Merge `spec/0.6.0-alpha.1-P14` into `feat/0.6.0-alpha.1`

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not run `signing configure`, `signing install-profiles`, or anything that writes `.env.dev`, `.env.release`, or `~/Library/MobileDevice`; the maintainer runs them.
- Do not accept `allow-any-userclient-access` or a wildcard.
- Change only the test assertions named in step 3; add new tests for the rest.
- Change only the files in `owns`; report a needed change elsewhere instead of making it.

History (from `events.jsonl`):

- 2026-10-14T01:04:20.628Z `doing` at `1178ab9d`
- 2026-10-14T01:12:08.527Z `verified` at `cffe96f3`, verify exit 0
- 2026-10-14T02:10:22.059Z `doing`, verdict `reject`; finding: driverkit.sh:291 _require_signed_host_access requires signed userclient-access == profile list; Host.entitlements signs [XboxUSBDevice], so a profile [XboxUSBDevice, VirtualHIDDevice] fails the build (REQ-26 not met); reproduced by reviewer; finding: docs/development/signing.md:15 claims such a profile works end to end; decision: `fix-code`
- 2026-10-14T02:11:28.191Z `verified` at `4bfe2c42`, verify exit 0
- 2026-10-14T02:26:45.515Z `approved` at `4bfe2c42`, verdict `approve`
- 2026-10-14T03:05:52.366Z `done` at `4bfe2c42`

## 6. P2: B3 snapshot packageProfiles and Packages watcher

- dotclaude status: `done`
- Wave: 2; deps: P1 (group 1); satisfies: REQ-4, REQ-5; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P2`; worktree: `.claude/worktrees/spec-P2`
- Owns: `Sources/OpenJoystickDriverKit/ApplicationService/RPC/ApplicationServiceRemappingRPC.swift`, `Sources/OpenJoystickDriverService/Runtime/RPC/RemappingRequestCoordinator+Operations.swift`, `Sources/OpenJoystickDriverService/Runtime/ApplicationServiceRuntime.swift`, `Resources/Schemas/v1beta1/cli-output.schema.json`, `Tests/OpenJoystickDriverKitTests/ApplicationService/RPC/ApplicationServiceRemappingSnapshotPayloadTests.swift`, `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/RemappingRequestCoordinatorTests+PackageProfiles.swift`, `Tests/OpenJoystickDriverServiceTests/Runtime/ProfileWatcherPackageTests.swift`
- Verify: `env -u TOOLCHAINS DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0 PATH=/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter 'RemappingRequestCoordinatorTests|ApplicationServiceRemappingSnapshotPayload|ProfileWatcherPackage'`

Goal:

The remapping snapshot lists each served package profile as `{profileID, package}`, and the running service reloads the profiles within the watcher debounce when `Packages/` changes.

Context:

- `design.md` section "B3".
- `ApplicationServiceRemappingRPC.swift:283-337` (snapshot payload; find with `grep -n "struct ApplicationServiceRemappingSnapshotPayload"`).
- `RemappingRequestCoordinator+Operations.swift` around `makeSnapshot` (~194).
- `RemappingProfileLibrary+Packages.swift:66-73` (`packageProfileSources()`).
- `ApplicationServiceRuntime.swift:152-192`, `Runtime/FileChangeWatcher.swift`, `ControllerRecordWatcher.swift:36`, and `Tests/OpenJoystickDriverServiceTests/Runtime/ControllerRecordWatcherPackageTests.swift` as the test model.
- The P1 report on `maximumProfileCount`.

- [x] 6.1 Add `public struct ApplicationServiceRemappingPackageProfile: Codable, Equatable, Sendable { profileID: UUID; package: String }` and `packageProfiles` to the snapshot payload, decoded with `decodeIfPresent ?? []`.
- [x] 6.2 If P1 found a profile-count check on decode, make it count only the profiles that are not in `packageProfiles`.
- [x] 6.3 Fill `packageProfiles` in `makeSnapshot` from `packageProfileSources()`, sorted by `profileID.uuidString`.
- [x] 6.4 If a CLI command prints the snapshot payload as JSON, add `packageProfiles` to the `$defs` entry of that command in `cli-output.schema.json`. Otherwise do not change the schema.
- [x] 6.5 In `startProfileWatcher`, watch the package store folder with `FileChangeWatcher` on the same debounce and call the existing profile reload. `startProfileWatcher` is `private` (`ApplicationServiceRuntime.swift:152`), so move its directory list and `watchesFile` predicate into one internal static function that `startProfileWatcher` calls; `ProfileWatcherPackageTests` drives a `FileChangeWatcher` built from that function over a temporary library directory and checks that an install-style rename of `Packages/<name>` calls `onChange`.
- [x] 6.6 Tests: payload round trip and missing-key decode; the snapshot lists a package profile; installing and removing a package through `ModPackageStore` in a temporary directory triggers a reload.
- [x] 6.7 Verify: the `verify` command above exits 0. Acceptance: The verify command passes. `./Scripts/ojd check schemas` passes if the schema changed.
- [x] 6.8 Review: a fresh reviewer agent approves the diff
- [x] 6.9 Merge `spec/0.6.0-alpha.1-P2` into `feat/0.6.0-alpha.1`

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only.
- CHANGELOG entries and wiki paragraphs stay on one line; doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py` (500 code lines in Sources, 1000 in Tests).
- Change only the files in `owns`; report a needed change elsewhere instead of making it.

History (from `events.jsonl`):

- 2026-10-14T03:06:27.695Z `doing` at `045b6345`
- 2026-10-14T03:06:27.943Z `doing` at `5c6a6e29`, verify exit 126
- 2026-10-14T03:07:14.668Z `verified` at `5c6a6e29`, verify exit 0
- 2026-10-14T03:16:21.055Z `approved` at `5c6a6e29`, verdict `approve`
- 2026-10-14T03:16:50.537Z `done` at `5c6a6e29`

## 7. P13: Signing doctor with regenerated host profiles

- dotclaude status: `done` (changes no file; verify ran in `.claude/worktrees/spec-P14` at `4bfe2c42`)
- Wave: 2; deps: P14 (group 5); satisfies: REQ-25; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P13`; worktree: `.claude/worktrees/spec-P13`
- Owns: no file
- Verify: `./Scripts/ojd signing doctor | tee /dev/stderr | grep -q '\[OK\] host profile grants user-client access'`

Goal:

`./Scripts/ojd signing doctor` passes with the host profiles the maintainer regenerated with `com.apple.developer.driverkit.userclient-access`.

Context:

- `design.md` section "Signing doctor (REQ-25)"; `justfile:176-177`.
- `Host.entitlements:16-20`, `Scripts/Signing/configure.py:261-291`, `Scripts/Build/driverkit.sh:178-229`.

- [x] 7.1 The maintainer installed the regenerated profiles on 2026-10-14 (`just signing-install-profiles`); both host profiles grant `userclient-access` to XboxUSBDevice and VirtualHIDDevice. P14 makes the checks accept that list. Before step 1, ask the maintainer to run `just signing-configure` if `.env.dev` still names old profiles.
- [x] 7.2 Read `./Scripts/ojd signing doctor` to find where it reads profiles (`~/Library/MobileDevice/Provisioning Profiles`, `~/Documents/Profiles/`, or another path).
- [x] 7.3 For each host profile there (`com.openjoystickdriver`, not the extension profiles), decode it (`openssl smime -inform der -verify -noverify -in`; `security cms -D` prints nothing in the sandbox) and check that its entitlements hold `com.apple.developer.driverkit.userclient-access` naming `com.openjoystickdriver.XboxUSBDevice`. If any lacks it, stop and report the profile and its date.
- [x] 7.4 Run `./Scripts/ojd signing doctor` and report its output. A `[SKIP]` line does not fail the doctor (`Scripts/Signing/doctor.py:325-333`), so the package is done only when the output has `[OK] host profile grants user-client access`; check that exact line in `doctor.py` first and fix the `verify` text in the report if it differs.
- [x] 7.5 Verify: the `verify` command above exits 0. Acceptance: The doctor exits 0, or the report names each missing entitlement or failing check.
- [x] 7.6 Review: a fresh reviewer agent approves the diff. One reviewer did not approve for lack of evidence (the doctor run in the sandbox found 0 signing identities); a later reviewer approved, and `events.jsonl` records `approved` at 2026-10-14T03:16:20Z
- [x] 7.7 Merge `spec/0.6.0-alpha.1-P13` into `feat/0.6.0-alpha.1`. No branch; P13 changes no file and was marked done after approval

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only.
- Doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py`.
- Change only the files in `owns`; report a needed change elsewhere instead of making it.
- Change no file; signing scripts and entitlements are not owned.

History (from `events.jsonl`):

- 2026-10-14T03:06:27.748Z `doing` at `045b6345`
- 2026-10-14T03:06:46.597Z `doing` at `045b6345`, verify exit 1; note: The command left changes outside `.dotclaude/spec`: .claude/worktrees/agent-a6ec4211cf41e0912/, .claude/worktrees/agent-adfb7ffcf65ee534f/, .claude/worktrees/spec-P1/, .claude/worktrees/spec-P10/, .claude/worktrees/spec-P14/, .claude/worktrees/spec-P15/, .claude/worktrees/spec-P2/, .claude/worktrees/spec-P3/, .claude/worktrees/spec-P4/, .claude/worktrees/spec-P9/.
- 2026-10-14T03:07:46.764Z `verified` at `4bfe2c42`, verify exit 0
- 2026-10-14T03:16:20.968Z `approved` at `4bfe2c42`, verdict `approve`
- 2026-10-14T03:16:50.538Z `done` at `4bfe2c42`

## 8. P15: Issue #18: list 045E:02D1 on the XboxUSBDevice DEXT route

- dotclaude status: `done`
- Wave: 2; deps: P10 (group 4); satisfies: REQ-24; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P15`; worktree: `.claude/worktrees/spec-P15`
- Owns: `Sources/OpenJoystickDriverUSB/Transport/USBDriverKitTransport.swift`, `Tests/OpenJoystickDriverKitTests/Device/Discovery/USB/XboxOne02D1DetectionTests.swift`
- Verify: `env -u TOOLCHAINS DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0 PATH=/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test -j 4 --filter XboxOne02D1Detection`

Goal:

The DEXT route lists `045E:02D1` while the XboxUSBDevice extension is active.
`USBDriverKitTransportProvider` reads the vendor, product, `locationID`, and the name strings from the DEXT service's parent `IOUSBHostDevice`.
It keeps the DEXT service's registry ID for the user-client open.

Context:

- `design.md` section "Xbox One 02D1 DEXT transport (REQ-24)" and section "Issue #18 (REQ-24)".
- P10 evidence: `docs/testing/xbox-one-02d1.md` (commit `43942623`, "Source Findings" 2 to 5, "Result").
  These facts come from reading the source.
  No hardware run confirms them.
- `Sources/OpenJoystickDriverUSB/Transport/USBDriverKitTransport.swift:6-22` (`devices()`, `physicalDeviceObservations()`, `servicesByID`), `:71-93` (`device(_:)`, which needs a scalar `idProduct`), `:95-112` (`physicalDeviceObservation(from:)`), and `:114-135` (property helpers).
- SwifterKit 0.3.0 (read only, `.build/checkouts/SwifterKit`): `DriverService` has only `id`, `name`, `registryPath`, and `properties` (`DriverKit/Models/DriverService.swift`). `IOKitDriverTransport.describe` reads the entry's own properties (`DriverKit/Transport/IOKitDriverTransport.swift:73-105`). `DriverProperty.decode` is internal (`IOKitDriverProperty.swift:10`), so OJD cannot use it. `DriverClient.init(transport:)` is public, and so is `DriverTransport` (`services(matching:)`, `open(_:type:)`).
- Registry patterns to copy: the parent walk in `Sources/OpenJoystickDriverKit/HID/HIDDeviceStream+DeviceProperties.swift:106-124` (`IOObjectConformsTo` with `IORegistryEntryGetParentEntry`), and the `IOUSBHostDevice` keys in `Sources/OpenJoystickDriverUSB/Transport/IOUSBHostTransport.swift:132-148` (`idVendor`, `idProduct`, `locationID`, `["USB Product Name", "Product Name"]`, `["USB Serial Number", "Serial Number"]`).
- `TransportFacade.swift:25` is the only call of `USBDriverKitTransportProvider(`. `selectDevices` (`:271-289`) and `driverKitObservation` (`:261-269`) compare the device with its observation field by field.
- `Tests/OpenJoystickDriverUSBTests/ConfigurationTests.swift:29-100` calls `device(service)` and `physicalDeviceObservation(from: service)` with one argument.
  Those calls must still compile and pass without a change.

- [x] 8.1 In `USBDriverKitTransport.swift`, add an internal value type `USBDriverKitParentDevice: Sendable, Hashable` with `vendorID: UInt16`, `productID: UInt16`, `locationID: UInt32?`, `productName: String?`, and `serialNumber: String?`.
- [x] 8.2 In the same file, add `static func registryParentDevice(serviceID: UInt64) -> USBDriverKitParentDevice?`.
  It runs `IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(serviceID))`, then walks `IORegistryEntryGetParentEntry(_, kIOServicePlane, _)` until `IOObjectConformsTo(entry, "IOUSBHostDevice")`.
  The walk stops after 8 levels.
  It releases every entry, and on the device node it reads the keys listed in Context with `IORegistryEntryCreateCFProperty` (not a recursive search).
  It returns nil when there is no ancestor or no `idVendor` and `idProduct`.
- [x] 8.3 Keep `public init(client:)` with the same signature and forward it to a new internal `init(client:parentDevice: @escaping @Sendable (UInt64) -> USBDriverKitParentDevice?)`.
  A public default argument cannot name an internal function.
  Store the closure and a `parentsByID: [UInt64: USBDriverKitParentDevice]`.
- [x] 8.4 In `devices()`, for each service, look up `parentDevice(service.id)`, fill `parentsByID` beside `servicesByID`, and return `services.compactMap { Self.device($0, parent: parentsByID[$0.id]) }`.
  In `physicalDeviceObservations()`, pass the cached parent so that the observation equals the listed device.
  Do not query the registry again there.
- [x] 8.5 Change `device(_:)` to `device(_ service: DriverService, parent: USBDriverKitParentDevice? = nil)`.
  Take each value from `parent` first and from the service properties second.
  Keep `serviceID: service.id` and the existing `locationID` fallback `UInt32(truncatingIfNeeded: service.id)`.
  Give `physicalDeviceObservation(from:parent:)` the same defaulted parameter.
  Doc comments wrap at 100 columns and say that the DEXT personality carries `idProductArray` when the extension lists more than one product.
- [x] 8.6 In `XboxOne02D1DetectionTests.swift`, replace only `dextServiceWithPersonalityPropertiesYieldsNoDevice`.
  The replacement is `dextServiceTakesIdentityFromParentUSBDevice`.
  It uses the same service and a parent `045E:02D1` with `locationID` `0x1410_0000`, a product name, and a serial number.
  It expects `.usbDriverKit`, `serviceID` 41, `02D1`, that location as both `locationID` and `observedPhysicalLocationIdentifier`, and the strings.
  Update the doc comment above it.
  Add these new tests:
  - `dextServiceWithoutParentYieldsNoDevice`: the same service with no parent still gives nil.
  - `providerListsDextServiceThroughParentLookup`: `USBDriverKitTransportProvider(client: DriverClient(transport: fake), parentDevice: { _ in parent })` with a test `DriverTransport` that returns the service and throws from `open`. `devices()` gives the 02D1 device, and `physicalDeviceObservations()` gives one observation whose fields equal that device.
  - `facadeSelectsDextRouteModel`: `selectDevices(direct: [direct], driverKit: [dext], supportedRawUSBModels: [model], requiredDriverKitModels: [model])` returns only the DEXT device.
- [x] 8.7 Watch `dextServiceTakesIdentityFromParentUSBDevice` and the provider test fail before step 4 and step 5, and say so in the report.
- [x] 8.8 Verify: the `verify` command above exits 0. Acceptance: The `verify` command passes. With the same env prefix, `swift test -j 4 --filter 'ConfigurationTests|TransportFacadeTests'` passes, and neither file has changed. `python3 Scripts/Quality/check_swift_file_length.py`, `swift-format lint --strict` on the two files, and `swiftlint lint --no-cache --strict` pass. The report names the residual risk H1.   A missing or refused `userclient-access` grant can still fail `client.open`, even though P14 widened the host profile check.   The report also says that hardware has not confirmed the fix.   It gives the `docs/testing/xbox-one-02d1.md` "Result" text for P6 or the maintainer to update, because P15 does not own that page.
- [x] 8.9 Review: a fresh reviewer agent approves the diff
- [x] 8.10 Merge `spec/0.6.0-alpha.1-P15` into `feat/0.6.0-alpha.1`

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`, and do not change SwifterKit.
- Do not change existing tests or limits; add new tests only.
  The one exception is the P10 test `dextServiceWithPersonalityPropertiesYieldsNoDevice`, which step 6 replaces.
  If `ConfigurationTests` or `TransportFacadeTests` fail, stop and report.
- Keep `public init(client:)` and `TransportFacade.swift` unchanged.
- Doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py` (500 code lines for Sources).
- Change only the files in `owns`; report a needed change elsewhere instead of making it.

History (from `events.jsonl`):

- 2026-10-14T03:07:27.427Z `doing` at `045b6345`
- 2026-10-14T03:07:31.642Z `verified` at `868059b3`, verify exit 0
- 2026-10-14T03:16:21.095Z `approved` at `868059b3`, verdict `approve`
- 2026-10-14T03:16:50.537Z `done` at `868059b3`

## 9. P3: ojd mod validate|install|list|remove

- dotclaude status: `done` (verify passed at `24656cbf`; approved; merged at `910e5b54`)
- Wave: 3; deps: P2 (group 6); satisfies: REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-17; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P3`; worktree: `.claude/worktrees/spec-P3`
- Owns: `Sources/OpenJoystickDriverCLI/Commands/Mod/ModCommand.swift`, `Sources/OpenJoystickDriverCLI/Commands/Mod/ModFileCommands.swift`, `Sources/OpenJoystickDriverCLI/Commands/Mod/ModReport.swift`, `Sources/OpenJoystickDriverCLI/CLI+OutputKind.swift`, `Sources/OpenJoystickDriverCLI/CLI.swift`, `Sources/OpenJoystickDriverCLI/Root/OJDCommand.swift`, `Resources/Schemas/v1beta1/cli-output.schema.json`, `Tests/OpenJoystickDriverCLITests/Commands/ModCommandTests.swift`, `Tests/OpenJoystickDriverCLITests/Root/CLIOutputSchemaTests.swift`, `Tests/OpenJoystickDriverCLITests/Support/CLIRun.swift`, `Resources/ErrorCodes.json`, `Sources/OpenJoystickDriverKit/Errors/ErrorCode.swift`, `wiki/Error-Codes.md`, `Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.strings`, `Sources/OpenJoystickDriverKit/Resources/C.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/en-US.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/ar-SA.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/de-DE.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/es-ES.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/es-MX.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/fr-CA.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/fr-FR.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/hi-IN.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/id-ID.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/it-IT.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/ja-JP.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/ko-KR.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/nl-NL.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/pt-BR.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/ru-RU.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/th-TH.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/tr-TR.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/vi-VN.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/zh-CN.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/zh-HK.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/zh-TW.lproj/Localizable.strings`
- Verify: `env -u TOOLCHAINS DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0 PATH=/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter 'ModCommandTests|CLIOutputSchemaTests|CommandTreeTests'`

Goal:

`ojd mod validate|install|list|remove` work with `--dry-run`, `--force`, and `--json`, print the apiVersion/kind envelope, and have one `$defs` entry each in `cli-output.schema.json`.

Context:

- `design.md` section "C".
- `Sources/OpenJoystickDriverCLI/Commands/Record/RecordCommand.swift`, `RecordFileCommands.swift`, `RecordReport.swift`.
- `Sources/OpenJoystickDriverCLI/CLI+OutputKind.swift`, `CLIOutput.swift`, `CLIStatus.swift`.
- `Sources/OpenJoystickDriverKit/Packages/ModPackageStore.swift:35-142`, `ModPackageStore+Validation.swift:32-74`, `ModPackageManifest.swift:1-41`.
- `Resources/Schemas/v1beta1/cli-output.schema.json` (the `record*` entries), `Resources/Schemas/AGENTS.md`.
- `Tests/OpenJoystickDriverCLITests/Commands/RecordCommandTests.swift`, `Root/CLIOutputSchemaTests.swift`, `Support/CLIRun.swift`.
- `LOCALIZATION.md`; the `cli.record.*` keys in `en-US.lproj/Localizable.strings`.

- [x] 9.1 Add the kinds to `CLI+OutputKind.swift` after the `record` rows (`:60-66`): `ModPackageValidation` (validate), `ModPackage` (install), `ModPackageList` (list), `Status` (remove). `ojd mod list` prints each package's `problem`, including the E4002 reason of a package that `requires` excludes (REQ-17, set by P1 in `ModPackageStore.list()`).
- [x] 9.2 Write `ModCommand` (group) and the four subcommands; register the group where `RecordCommand` is registered (find it with `grep -rn "RecordCommand.self" Sources/OpenJoystickDriverCLI`; if that file is not `CLI.swift`, stop and report).
- [x] 9.3 `install` and `remove` call `ModPackageStore` directly; `--force` passes `replace: true`; `--dry-run` validates (and checks existence for remove) and writes nothing.
- [x] 9.4 Map `ModPackageError` to its E4xxx code and the refused-input exit code that `record` uses. Add no new code unless needed; if one is added, run `./Scripts/ojd errors regenerate --write`.
- [x] 9.5 Add `modValidate`, `modInstall`, `modList`, `modRemove` to `cli-output.schema.json` (strict, `additionalProperties: false`).
- [x] 9.6 Add every `cli.mod.*` key to the template and all 22 catalogs (English text in `en-US` and `C`; other locales get a translation for P7 to review).
- [x] 9.7 Tests with a temporary store: each command, `--json` output against the schema, `--force` refused on clash and on `requires`, `--dry-run` writes nothing, `remove` of a missing name is E4006.
- [x] 9.8 Verify: the `verify` command above exits 0. Acceptance: The verify command passes. `./Scripts/ojd check schemas` and `python3 Scripts/Quality/check_localization_keys.py` pass.
- [x] 9.9 Review: a fresh reviewer agent approves the diff. Verdict `VERDICT P3: approve` (2026-10-14) with one should-fix and two nits (see Open items); recorded here on 2026-10-14 after the move to OpenSpec
- [x] 9.10 Merge `spec/0.6.0-alpha.1-P3` into `feat/0.6.0-alpha.1`. Merged at `910e5b54`; the `verify` command passed on the merged tree (25 tests in 3 suites)

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only.
- CHANGELOG entries and wiki paragraphs stay on one line; doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py` (500 code lines in Sources, 1000 in Tests).
- Change only the files in `owns`; report a needed change elsewhere instead of making it.

History (from `events.jsonl`):

- 2026-10-14T03:17:09.223Z `doing` at `9608bebc`
- 2026-10-14T03:28:50.940Z `verified` at `24656cbf`, verify exit 0
- 2026-10-14 `approved` at `24656cbf`, verdict `approve` (recorded in OpenSpec)
- 2026-10-14 `done`, merged at `910e5b54`

## 10. P5: Sample package and its test

- dotclaude status: `done` (verify passed at `a73e4201`; approved; merged at `158b23d5`)
- Wave: 4; deps: P3 (group 9); satisfies: REQ-13; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P5`; worktree: `.claude/worktrees/spec-P5`
- Owns: `docs/sdk/sample/mod.json`, `docs/sdk/sample/Controllers/`, `docs/sdk/sample/Profiles/`, `docs/sdk/sample/Personas/`, `Tests/OpenJoystickDriverCLITests/Commands/SampleModPackageTests.swift`, `Tests/OpenJoystickDriverCLITests/Fixtures/SampleModPackage/`, `Package.swift` (exclude `Fixtures` from the CLI test target)
- Verify: `env -u TOOLCHAINS DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0 PATH=/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter SampleModPackageTests`

Goal:

`docs/sdk/sample/` holds a package with one record, one profile, and one persona that `ojd mod validate` accepts, and `swift test` validates it and runs `ojd record test` on its record.

Context:

- `design.md` section "D".
- `Resources/Schemas/v1beta1/mod-package.schema.json`, `controller.schema.json`, `profile` and `persona` schemas.
- `ModPackageManifest.swift:17-111` (schema ID and file-name patterns), `ModPackageStore+Validation.swift:79-143`.
- `Tests/OpenJoystickDriverCLITests/Commands/RecordTestCommandTests.swift` and its fixtures (capture and expected state format).
- `Sources/OpenJoystickDriverCLI/Commands/Record/RecordTestCommand.swift`.
- `Package.swift`, to check how test fixtures are found (resources or `#filePath`).

- [x] 10.1 Write `mod.json` with `name` `ojd-sample`, `version` `1.0.0`, `requires` `{"minimum": "0.6.0-alpha.1", "below": "0.7.0"}`, and the three file lists.
- [x] 10.2 Write one record whose VID:PID is not in the bundled catalog, one profile for it, and one persona, each valid under its schema and file-name rule. Use decimal JSON.
- [x] 10.3 Put the `record test` capture and expected state in the fixture folder, not in the package.
- [x] 10.4 Write `SampleModPackageTests`: run `ojd mod validate docs/sdk/sample --json` and `ojd record test` on the record with the fixture, both through `CLIRun`, with a temporary store.
- [x] 10.5 Verify: the `verify` command above exits 0. Acceptance: The verify command passes. `./Scripts/ojd check schemas` and `./Scripts/ojd check profiles` pass. Passed: 2 tests in 1 suite; `check schemas` and `check profiles` exit 0. `Package.swift` now excludes `Fixtures` from the CLI test target to silence the unhandled-files warning
- [x] 10.6 Review: a fresh reviewer agent approves the diff. Verdict `VERDICT P5: approve` (2026-10-14), no blocking or should-fix findings; two nits: the fixture covers 2 of 8 buttons and no negative axes, and the `#filePath` chains in `SampleModPackageTests.swift:8-16` repeat
- [x] 10.7 Merge `spec/0.6.0-alpha.1-P5` into `feat/0.6.0-alpha.1`. Merged at `158b23d5`; the `verify` command passed on the merged tree (2 tests in 1 suite)

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only.
- CHANGELOG entries and wiki paragraphs stay on one line; doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py` (500 code lines in Sources, 1000 in Tests).
- Change only the files in `owns`; report a needed change elsewhere instead of making it.

## 11. P11: Ownership toggle: CLI, service RPC, live re-apply

- dotclaude status: `done`
- Wave: 4; deps: P1 (group 1), P3 (group 9); satisfies: REQ-18, REQ-20, REQ-21, REQ-22; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P11`; worktree: `.claude/worktrees/spec-P11`
- Owns: `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerOwnershipWriter.swift`, `Sources/OpenJoystickDriverKit/Protocol/Catalog/ControllerRecordSet.swift` (a user patch applies over an installed package record when no bundled record exists, maintainer decision 2026-10-14), `Sources/OpenJoystickDriverKit/HID/HIDDeviceStream+DeviceLifecycle.swift`, `Sources/OpenJoystickDriverKit/HID/Session.swift`, `Sources/OpenJoystickDriverKit/Device/Manager/DeviceManager+Lifecycle.swift`, `Sources/OpenJoystickDriverKit/ApplicationService/Client/ApplicationServiceClient+Requests.swift`, `Sources/OpenJoystickDriverKit/ApplicationService/RPC/ApplicationServiceRPCMethod.swift`, `Sources/OpenJoystickDriverKit/ApplicationService/Payloads/ControllerOwnershipPayloads.swift`, `Sources/OpenJoystickDriverService/Runtime/RPC/LocalRPCBridge.swift`, `Sources/OpenJoystickDriverService/Runtime/RPC/ControllerOwnershipRequests.swift`, `Sources/OpenJoystickDriverKit/Bluetooth/Switch2BluetoothLERouting.swift`, `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/LocalRPCBridgeTests.swift`, `Tests/OpenJoystickDriverServiceTests/Runtime/RPC/ControllerOwnershipRequestsTests.swift`, `Sources/OpenJoystickDriverCLI/Commands/Controller/ControllerCommand.swift`, `Sources/OpenJoystickDriverCLI/Commands/Controller/ControllerReport.swift`, `Sources/OpenJoystickDriverCLI/Commands/Controller/ControllerOwnershipCommand.swift`, `Sources/OpenJoystickDriverCLI/CLI+OutputKind.swift`, `Resources/Schemas/v1beta1/cli-output.schema.json`, `Resources/ErrorCodes.json`, `Sources/OpenJoystickDriverKit/Errors/ErrorCode.swift`, `wiki/Error-Codes.md`, `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerOwnershipWriterTests.swift`, `Tests/OpenJoystickDriverKitTests/Device/Manager/OwnershipReapplyTests.swift`, `Tests/OpenJoystickDriverCLITests/Commands/ControllerOwnershipCommandTests.swift`, `Tests/OpenJoystickDriverCLITests/Support/CLIRun.swift` (one sample-operand case for `controller ownership`, which `CommandTreeTests` parses at every leaf; no assertion changes), `Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.strings`, `Sources/OpenJoystickDriverKit/Resources/C.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/en-US.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/ar-SA.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/de-DE.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/es-ES.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/es-MX.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/fr-CA.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/fr-FR.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/hi-IN.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/id-ID.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/it-IT.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/ja-JP.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/ko-KR.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/nl-NL.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/pt-BR.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/ru-RU.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/th-TH.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/tr-TR.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/vi-VN.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/zh-CN.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/zh-HK.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/zh-TW.lproj/Localizable.strings`
- Verify: `env -u TOOLCHAINS DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0 PATH=/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter 'ControllerOwnership|OwnershipReapply|LocalRPCBridgeTests|ControllerCommandTests|CLIOutputSchemaTests|CommandTreeTests'`

Goal:

`ojd controller ownership CONTROLLER native|virtual [--dry-run] [--json]` writes the user record's `ownership`, the service applies it to a connected controller without replugging, `controller show` reports the choice and its source, a raw-USB or non-native controller is refused with E2023, and the service RPC that P12 calls exists.

Context:

- `design.md` section "Ownership toggle (REQ-18..22)" and decisions D4-D6.
- `DeviceCatalog.swift:40-44`, `TransportProfiles.swift:207-214`, `ControllerRecordDocument.swift:23,53`, `ControllerRecordSet.swift:5-15` (layers; P1 owns this file, read only).
- `HIDDeviceStream+DeviceLifecycle.swift:13-95,192-235`, `Session.swift:69-101`, `DeviceManager+Lifecycle.swift:78-124`, `ControllerRecordWatcher.swift`.
- `DevicePipeline.swift:158-159`, `DevicePipeline+InputEvents.swift:57`, `DeviceManager+HIDAdmission.swift:198`, `ControllerExposureDecision.swift` (read only).
- `RecordFileCommands.swift:126-225` (write and `--dry-run` form), `ControllerCommand.swift:104-303`, `ControllerReport.swift:1-200`, `ControllerSelector.swift`.
- `ApplicationServiceClient+Requests.swift:164` (`setVirtualHIDProfileOverride`) as the RPC model; its service handler (find with `grep -rn setVirtualHIDProfileOverride Sources/OpenJoystickDriverService`).
- `CLI+OutputKind.swift`, `cli-output.schema.json` (`controllerShow`), `Resources/ErrorCodes.json:192-210`, `LOCALIZATION.md`.

- [x] 11.1 `ControllerOwnershipWriter` (Kit): set or replace `ownership` in `Controllers/<vvvv>-<pppp>.json`, creating a `patch` record when the file is missing and the model has a bundled or package record; a model with no record is refused with E2023 and a detail that points to `ojd record draft` (maintainer decision, a `patch` cannot apply without a base record, `ControllerRecordSet.swift:320-325`); validate with `ControllerRecordSet.validate`; write atomically; refuse an invalid existing file. Tests: new file, merge keeps other keys, invalid file refused, `--dry-run` writes nothing.
- [x] 11.2 Live re-apply: add `reevaluateOwnership(of:)` to `HIDDeviceStream`. For a changed identity whose recomputed `nativePassThrough` differs, remove every tracked interface of that device first and only then add them all again, so no sibling interface keeps the old native flag (`HIDDeviceStream+DeviceLifecycle.swift:73`). Leave the re-evaluated connections out of `readmitHIDConnections` (`DeviceManager+Lifecycle.swift:96-123`) so a device is not admitted twice. Add the requirement to `HIDAccessBackend` (`Session.swift:69-101`) with a default no-op in a protocol extension, so the test fakes in `Tests/OpenJoystickDriverKitTests/Device/Support/` need no change, and forward it in `BluetoothLECompositeHIDBackend` (`Switch2BluetoothLERouting.swift:6`). Call it from `reloadControllerRecords`. Test with the existing fake backend that a changed identity is re-added with the new value and others are untouched.
- [x] 11.3 Test that a native-capable model with `ownership: ojd` and a passthrough profile gets a pipeline with nil `observedInputDemand` and dispatches each changed report (no gate change; design "Dispatch").
- [x] 11.4 Add E2023 to `Resources/ErrorCodes.json`, run `./Scripts/ojd errors regenerate --write`.
- [x] 11.5 `ControllerOwnershipCommand` in `ControllerOwnershipCommand.swift`, registered in `ControllerCommand.subcommands`; kind `ControllerOwnership`; `$defs.controllerOwnership`; refuse raw-USB or non-native with E2023 and the reason.
- [x] 11.6 `controller show`: add `choice` and `choiceSource` to `ControllerShowReport.Ownership` and the schema `controllerShow` entry. Take `choiceSource` from `fieldLayers["ownership"]` (`ControllerRecordSet.swift:36`), not from the record's top `layer` (`ControllerReport.swift:92-93`). Print them in a new human row with a new key `cli.controller.show.ownershipChoice`; do not change `cli.controller.show.ownership`, which `ControllerCommandTests.swift:236-242` pins.
- [x] 11.7 RPC `setControllerOwnership(identity:ownership:)`: the method in `ApplicationServiceRPCMethod.swift`, the payload in the new `ControllerOwnershipPayloads.swift` (model: `ApplicationService/Payloads/VirtualHIDProfileOverridePayloads.swift`), the client call beside `setVirtualHIDProfileOverride` (`ApplicationServiceClient+Requests.swift:164`), the handler in the new `ControllerOwnershipRequests.swift` (model: `Service/Runtime/RPC/VirtualHIDProfileOverrideRequests.swift`), and its route in `LocalRPCBridge.swift:146`. Add `setControllerOwnership` to the pinned method set in `LocalRPCBridgeTests.swift:9-34`; that one name is the only change to an existing test (maintainer approval, 2026-10-14). Test the handler in `ControllerOwnershipRequestsTests.swift`.
- [x] 11.8 Add `cli.controller.ownership.*`, `error.E2023`, and the app keys `controllers.ownership.*` (label, native, virtual, refused) to the template and all 22 catalogs (English in `en-US` and `C`, translations for P7).
- [x] 11.9 Verify: the `verify` command above exits 0. Acceptance: The verify command passes; `./Scripts/ojd check schemas`, `python3 Scripts/Quality/check_localization_keys.py`, and `./Scripts/ojd errors regenerate --check` (or the repo's equivalent) pass. The report lists the hardware check for the maintainer: toggle a connected 8BitDo `2DC8:301B` to virtual and run `ojd --headless test`.
- [x] 11.10 Review: a fresh reviewer agent approves the diff. Verdict `approve` (2026-10-14) with two should-fix items and nits (see Open items)
- [x] 11.11 Merge `spec/0.6.0-alpha.1-P11` into `feat/0.6.0-alpha.1`. Merged at `8be61078`, whose tree equals the verified `8f8bf838`; the full `swift test` passed on it (2549 tests in 350 suites)

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only. The one exception is the added method name in `LocalRPCBridgeTests.swift`.
- Doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py`.
- Change only the files in `owns`; report a needed change elsewhere instead of making it.

## 12. P6: Mod docs and CHANGELOG

- dotclaude status: `done` (verify passed at `05199978`; approved; merged at `53acb754`)
- Wave: 5; deps: P3 (group 9), P5 (group 10), P9 (group 3), P10 (group 4), P11 (group 11); satisfies: REQ-14, REQ-15, REQ-24; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P6`; worktree: `.claude/worktrees/spec-P6`
- Owns: `wiki/Writing-Controller-Mods.md`, `wiki/Command-Line.md`, `wiki/Command-Reference.md`, `wiki/Controller-Records.md`, `wiki/_Sidebar.md`, `wiki/Home.md`, `wiki/Known-Issues.md`, `CHANGELOG.md`
- Verify: `git ls-files -z -co --exclude-standard -- '*.md' ':!.agents/' | xargs -0 markdownlint-cli2`

Goal:

The wiki describes the mod packages that ship, and `CHANGELOG.md` lists them on one line each.

Context:

- `wiki/AGENTS.md` (style, Home and Sidebar rules, no source paths).
- `wiki/Home.md`, `wiki/_Sidebar.md`, `wiki/Command-Line.md`, `wiki/Command-Reference.md`, `wiki/Controller-Records.md`.
- `docs/development/cli-config-sdk-plan.md:81-104`.
- The `ojd mod` help text from P3 and `docs/sdk/sample/` from P5.
- `CHANGELOG.md` `[Unreleased]` section.

- [x] 12.1 Write `wiki/Writing-Controller-Mods.md`. Its first statement after the H1 says that the product list of the USB extension is Apple-signed and cannot be extended by a package. Then cover layout, `mod.json`, precedence, clashes, read-only profiles, and the `ojd mod` commands, with the sample package as the example.
- [x] 12.2 Add the page to `wiki/Home.md` and `wiki/_Sidebar.md` in the same group.
- [x] 12.3 Update `Command-Line.md`, `Command-Reference.md`, and `Controller-Records.md` with what ships.
- [x] 12.4 In `CHANGELOG.md` `[Unreleased]`, add one line each: mod packages and `ojd mod` (with the runtime skip of a package that `requires` excludes), E3029, E4001-E4007.
- [x] 12.5 Also add one `[Unreleased]` line each for the native/virtual ownership toggle (`ojd controller ownership`, the app picker, E2023), the stick stutter fix that P9 reports, and the issue #18 result that P10 reports. In `Command-Reference.md` add `controller ownership`; in `Controller-Records.md` replace the claim of line 45 with what P11 ships. If P10 found the cause outside OJD, add its line to `wiki/Known-Issues.md`.
- [x] 12.6 Rename `## [Unreleased]` to `## [0.6.0-alpha.1] - <date>` with `date -u +%F` of the day the package runs, and add a compare link if the file has link references (maintainer decision D3).
  The report names the date, so the maintainer can correct it in the release commit if the approval falls on another day.
- [x] 12.7 Verify: the `verify` command above exits 0. Acceptance: The verify command passes. Each new wiki paragraph and CHANGELOG entry is one line.
- [x] 12.8 Review: a fresh reviewer agent approves the diff
- [x] 12.9 Merge `spec/0.6.0-alpha.1-P6` into `feat/0.6.0-alpha.1`

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only.
- CHANGELOG entries and wiki paragraphs stay on one line; doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py` (500 code lines in Sources, 1000 in Tests).
- Change only the files in `owns`; report a needed change elsewhere instead of making it.

## 13. P7: l10n review of mod strings

- dotclaude status: `done` (verify passed at `735dda2c`; approved; merged at `57a461ff`)
- Wave: 5; deps: P3 (group 9), P11 (group 11); satisfies: REQ-12, REQ-18, REQ-19; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P7`; worktree: `.claude/worktrees/spec-P7`
- Owns: `Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.strings`, `Sources/OpenJoystickDriverKit/Resources/C.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/en-US.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/ar-SA.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/de-DE.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/es-ES.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/es-MX.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/fr-CA.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/fr-FR.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/hi-IN.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/id-ID.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/it-IT.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/ja-JP.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/ko-KR.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/nl-NL.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/pt-BR.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/ru-RU.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/th-TH.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/tr-TR.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/vi-VN.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/zh-CN.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/zh-HK.lproj/Localizable.strings`, `Sources/OpenJoystickDriverKit/Resources/zh-TW.lproj/Localizable.strings`
- Verify: `python3 Scripts/Quality/check_localization_keys.py && env -u TOOLCHAINS DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0 PATH=/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter OpenJoystickDriverKitTests.LocalizationTests`

Goal:

`error.E3029`, `error.E4001`-`error.E4007`, `cli.explain.area.mod`, every `cli.mod.*` value, and the toggle keys of P11 (`cli.controller.ownership.*`, `controllers.ownership.*`, `error.E2023`, and the changed `cli.controller.show.ownership`) are reviewed in every catalog under `LOCALIZATION.md`.

Context:

- `LOCALIZATION.md` (all of it).
- `en-US.lproj/Localizable.strings`: the keys named in the goal.
- `git diff` of the 22 catalogs for the B1 renumbering.
- The call sites of `cli.mod.*` in `Sources/OpenJoystickDriverCLI/Commands/Mod/`.

- [x] 13.1 For each locale, check that `error.E3029` holds the old E4007 sense and `error.E4007` the old E4008 sense.
- [x] 13.2 Read each value back against `en-US`. Fix the sense, punctuation (native quotes and ellipsis, no ASCII `"`), and terms (package, profile). Keep `mod.json`, `ojd mod list`, `--force`, and placeholders.
- [x] 13.3 Review the toggle keys of P11 the same way; keep `native`, `virtual`, and `ojd controller ownership` as the CLI spells them where they are command values.
- [x] 13.4 Keep keys and the key order unchanged.
- [x] 13.5 Verify: the `verify` command above exits 0. Acceptance: The verify command passes. The report lists each changed value by locale and key.
- [x] 13.6 Review: a fresh reviewer agent approves the diff
- [x] 13.7 Merge `spec/0.6.0-alpha.1-P7` into `feat/0.6.0-alpha.1`

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only.
- CHANGELOG entries and wiki paragraphs stay on one line; doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py` (500 code lines in Sources, 1000 in Tests).
- Change only the files in `owns`; report a needed change elsewhere instead of making it.

## 14. P12: Ownership toggle in the app

- dotclaude status: `done` (verify passed at `eeab0f8a`; approved; merged at `5a886f11`)
- Wave: 5; deps: P11 (group 11); satisfies: REQ-19; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P12`; worktree: `.claude/worktrees/spec-P12`
- Owns: `Sources/OpenJoystickDriverPresentation/Controllers/Inventory/ControllerOwnershipPicker.swift`, `Sources/OpenJoystickDriverPresentation/Controllers/Inventory/ControllerDetailView+Facts.swift`, `Sources/OpenJoystickDriverPresentation/Runtime/ApplicationServiceGateway.swift`, `Sources/OpenJoystickDriverPresentation/Runtime/ApplicationServiceClientGateway+Requests.swift`, `Sources/OpenJoystickDriverPresentation/Runtime/RuntimeViewModel+ControllerActions.swift`, `Tests/OpenJoystickDriverPresentationTests/Support/GatewayStub.swift`, `Tests/OpenJoystickDriverPresentationTests/Controllers/ControllerOwnershipPickerTests.swift`, `Sources/OpenJoystickDriverKit/ApplicationService/Payloads/ApplicationServiceDeviceDescription.swift`, `Sources/OpenJoystickDriverKit/Device/Manager/ConnectedDeviceSnapshot.swift`, `Sources/OpenJoystickDriverKit/Device/Manager/DeviceManager+Queries.swift`, `Tests/OpenJoystickDriverKitTests/Device/Manager/RecordOwnershipReportTests.swift` (the Kit files joined on 2026-10-14: the app has no record ownership, so a model switched to Virtual would lose its picker; the device payload gains the effective record ownership)
- Verify: `grep -q ControllerOwnershipPicker Sources/OpenJoystickDriverPresentation/Controllers/Inventory/ControllerDetailView+Facts.swift && env -u TOOLCHAINS DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0 PATH=/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter ControllerOwnershipPicker`

Goal:

The app's controller detail shows Native / Virtual for each connected controller that macOS supports natively, next to the virtual profile override, and changes it through the `setControllerOwnership` RPC that P11 adds.

Context:

- `design.md` section "Ownership toggle", item "App", and decision D6.
- `Sources/OpenJoystickDriverPresentation/Controllers/Inventory/ControllerDetailView+Facts.swift:30`, which holds `VirtualHIDProfileOverrideView.swift` (the model for the new view).
- The call chain for `setVirtualHIDProfileOverride`: `Runtime/ApplicationServiceGateway.swift:91`, `Runtime/ApplicationServiceClientGateway+Requests.swift`, `Runtime/RuntimeViewModel+ControllerActions.swift`, and the test stub `Tests/OpenJoystickDriverPresentationTests/Support/GatewayStub.swift:31`.
- `ApplicationServiceClient+Requests.swift` (`setControllerOwnership`, added by P11, read only); `controllers.ownership.*` and `error.E2023` keys added by P11.

- [x] 14.1 Add `setControllerOwnership(identity:ownership:)` to `ApplicationServiceGateway`, implement it in `ApplicationServiceClientGateway+Requests.swift`, and add the view-model action in `RuntimeViewModel+ControllerActions.swift`, following `setVirtualHIDProfileOverride`.
- [x] 14.2 Add the matching method to `GatewayStub.swift` so it records the call; change nothing else in that file.
- [x] 14.3 Write `ControllerOwnershipPicker` (a two-value picker, Native / Virtual): shown only when the device's `physicalOwnership` is `nativeGamepad`, or its record ownership is `ojd`, and its family is not raw-USB. On change it calls the view-model action and shows E2023 with its localized text.
- [x] 14.4 Place it in `ControllerDetailView+Facts.swift` beside `VirtualHIDProfileOverrideView` (`:30`).
- [x] 14.5 Test the visibility rule and that a change calls the gateway with the right identity and value, with `GatewayStub`.
- [x] 14.6 Verify: the `verify` command above exits 0. Acceptance: The verify command passes; `python3 Scripts/Quality/check_localization_keys.py` passes. The report lists the maintainer's manual check: open a native controller's detail, switch to Virtual, and see the virtual gamepad in a game.
- [x] 14.7 Review: a fresh reviewer agent approves the diff
- [x] 14.8 Merge `spec/0.6.0-alpha.1-P12` into `feat/0.6.0-alpha.1`

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only. The one exception is the added stub method in `GatewayStub.swift`, which the protocol change needs; the maintainer approved it on 2026-10-14.
- Do not add localized keys; P11 adds them and P7 owns the catalogs in this wave.
- Doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py`.
- Change only the files in `owns`; report a needed change elsewhere instead of making it.

## 15. P8: Full check list

- dotclaude status: `in review` (checks run at `5b43e065`; 15.5 open: `just check` stops at `ojd check tools`, owner: environment; approved; merged at `856a5cdf`)
- Wave: 6; deps: P1 (group 1), P2 (group 6), P3 (group 9), P4 (group 2), P5 (group 10), P6 (group 12), P7 (group 13), P9 (group 3), P10 (group 4), P11 (group 11), P12 (group 14), P13 (group 7), P14 (group 5); satisfies: REQ-16; agent: `implementer`
- Branch: `spec/0.6.0-alpha.1-P8`; worktree: `.claude/worktrees/spec-P8`
- Owns: no file
- Verify: `env -u TOOLCHAINS DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer OJD_USE_LOCAL_SWIFTERKIT=0 PATH=/Applications/Xcode-26.6.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH sh -c 'just check && ./Scripts/ojd test parsers-macos14'`

Goal:

Every command in the `CLAUDE.md` Checks list and `./Scripts/ojd test parsers-macos14` exit 0 on the final tree.

Context:

- `CLAUDE.md` "Checks".
- `design.md` section "Full check".
- `justfile`, to see if `just check` runs each command of the list.

- [x] 15.1 Set the toolchain environment of the design and record `swift --version`.
- [x] 15.2 Run each command of the `CLAUDE.md` Checks list one at a time, then `./Scripts/ojd test parsers-macos14`.
- [x] 15.3 Report each failure with its command and first error. Do not fix code; a failure goes back to the package that owns the file.
- [x] 15.4 If `./Scripts/ojd check schemas` fails only with the user toolchain first on `PATH`, record both runs.
- [ ] 15.5 Verify: the `verify` command above exits 0. Acceptance: Each command exits 0, or the report lists each failure with its owner package.
- [x] 15.6 Review: a fresh reviewer agent approves the diff
- [x] 15.7 Merge `spec/0.6.0-alpha.1-P8` into `feat/0.6.0-alpha.1`

Boundaries:

- Do not commit or push; the maintainer approves each commit.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`.
- Do not change existing tests or limits; add new tests only.
- CHANGELOG entries and wiki paragraphs stay on one line; doc comments wrap at 100 columns.
- Swift files obey `python3 Scripts/Quality/check_swift_file_length.py` (500 code lines in Sources, 1000 in Tests).
- Change only the files in `owns`; report a needed change elsewhere instead of making it.

## 16. P16: Open-item fixes

- dotclaude status: `planned`
- Wave: 7; deps: P8 (group 15), P11 (group 11), P12 (group 14), P15 (group 8); satisfies: the open items of P8, P11, P12, and P15; agent: main session
- Branch: `spec/0.6.0-alpha.1-P16`; worktree: `.claude/worktrees/spec-P16`
- Owns:
  - `Scripts/Command/dispatcher.py`
  - `Tests/RepositoryScripts/test_dispatcher.py` (new tests only)
  - `Sources/OpenJoystickDriverKit/Device/Manager/DeviceManager.swift`
  - `Sources/OpenJoystickDriverKit/Device/Manager/DeviceManager+Lifecycle.swift`
  - `Sources/OpenJoystickDriverKit/Device/Discovery/HID/DeviceManager+HIDTeardown.swift`
  - `Tests/OpenJoystickDriverKitTests/Device/Manager/OwnershipSuspensionTests.swift` (new)
  - `Sources/OpenJoystickDriverPresentation/Runtime/RuntimeViewModel+ControllerActions.swift`
  - `Sources/OpenJoystickDriverPresentation/Runtime/LabelsAndDetection.swift`
  - `Sources/OpenJoystickDriverPresentation/Runtime/RuntimeStatusPresentation+Messages.swift` (added during 16.3: the status equality ignored `recordOwnership`, so a refresh never showed the new value)
  - `Tests/OpenJoystickDriverPresentationTests/Controllers/ControllerOwnershipPickerTests.swift` (the maintainer allowed one change, 2026-10-14: `aRefusalShowsE2023WithTheServiceDetail` expects the new invalid-record text)
  - `Tests/OpenJoystickDriverPresentationTests/Controllers/ControllerOwnershipFeedbackTests.swift` (new)
  - `Sources/OpenJoystickDriverKit/Resources/*.lproj/Localizable.strings` and `Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.strings`, for three `controllers.ownership.*` keys
  - `docs/testing/xbox-one-02d1.md` ("Result" only)
- Verify: the `CLAUDE.md` Checks list, `./Scripts/ojd test parsers-macos14`, and the P8 `verify` command (group 15)

Goal:

Resolve the open items that the maintainer asked to fix (2026-10-14).

- [ ] 16.1 `ojd check tools` runs xmake with the SDK of the selected Xcode: it sources `Scripts/Platform/environment.sh`, which exports `SDKROOT`. A new dispatcher test covers it.
- [ ] 16.2 An ownership toggle keeps the suspension of a suspended controller that the HID backend admits again; a physical disconnect still ends it. A new Kit test covers both.
- [ ] 16.3 After a successful toggle, the app polls the inventory until the model's `recordOwnership` matches the request, for at most 2 seconds, and the status equality compares `recordOwnership`. A new test covers it.
- [ ] 16.4 `noRecord`, `invalidRecord`, and `persistenceFailed` show their own `controllers.ownership.*` texts in every locale; `rawUSB` and `notNative` keep `error.E2023`.
- [ ] 16.5 `docs/testing/xbox-one-02d1.md` "Result" says the parent-device fix landed in P15 and is not verified on hardware.
- [ ] 16.6 Verify: every check above exits 0.
- [ ] 16.7 Review: a fresh reviewer agent approves the diff
- [ ] 16.8 Merge `spec/0.6.0-alpha.1-P16` into `feat/0.6.0-alpha.1`

## Hardware checks (maintainer)

These need physical controllers and are left to the maintainer at the end:

- P9: stick stutter in a GameController game, CrossOver, and a browser; if needed, timestamps at dispatch and at `IOHIDUserDeviceHandleReport` with a game open.
- P10 and P15: `045E:02D1` is listed on the DEXT route with the XboxUSBDevice extension active (risk H1 in `design.md`).
- P11 and P12: toggle a connected 8BitDo `2DC8:301B` to virtual, run `ojd --headless test`, and see the virtual gamepad in a game.
- P13: `./Scripts/ojd signing doctor` outside the sandbox prints `[OK] host profile grants user-client access to com.openjoystickdriver.XboxUSBDevice` and exits 0.

## Workflow follow-up

- Each commit needs the maintainer's approval at the commit points in `design.md`, unless the working agreements above cover it.
- Push, CI, tagging, notarizing, `just package-tester`, and publishing need the maintainer's approval.
- Archive this change with `openspec archive release-0-6-0-alpha-1` after every group is done.
