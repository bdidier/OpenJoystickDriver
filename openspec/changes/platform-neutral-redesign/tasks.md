# Tasks: platform-neutral redesign

This is a plan. No task here is done. Each work package (WP) lists what it owns, what it depends on, and the checks that prove it. Order follows dependencies: tests first, then data, then identity, then behavior, then surfaces.

## Working agreements

- The user's decisions are in `design.md`. Where a choice was assumed, the "Assumed (veto-able)" table there lists it.
- Do not edit generated records in `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`. Change authored inputs, then run `./Scripts/ojd catalog regenerate --write` and `./Scripts/ojd driverkit generate`.
- No SVGs, no secrets. Confirm destructive writes and publication before running them.
- Every task states how to verify it. A task is done only after that check ran in the session that closes it.
- "Check list" below means the commands in the repository `CLAUDE.md`:
  - `./Scripts/ojd catalog regenerate --check`
  - `./Scripts/ojd check profiles`
  - `./Scripts/ojd check schemas`
  - `ruff format --check Scripts Tests/RepositoryScripts`
  - `ruff check Scripts Tests/RepositoryScripts`
  - `pyright`
  - `.build/schema-validator/bin/python -m unittest discover -s Tests/RepositoryScripts`
  - shellcheck over `Scripts`
  - markdownlint over tracked and untracked `.md` files outside `.agents/`
  - `swift-format lint --recursive --strict Package.swift Sources Tests`
  - `swiftlint lint --no-cache --strict`
  - `python3 Scripts/Quality/check_swift_file_length.py`
  - `python3 Scripts/Quality/check_localization_keys.py`
  - `./Scripts/ojd check driverkit`
  - `swift test`
  - for parser or protocol changes, also `./Scripts/ojd test parsers-macos14`
- Use `./Scripts/ojd repair swiftpm-module-cache` only to repair a module-cache mismatch.

## Open items

These need the user or hardware. Tasks that depend on them say so.

1. Which DS3 location (`01130000` or `01140000`) is the genuine CECHZC2E (0xEF discriminator).
2. Settled: stay with the seven granted `transport.usb` IDs (`design.md` Open Questions).
3. Settled: catalog-wide localization choices, applied by 22.6 (`design.md` Open Questions).
4. Settled: the command-line tool link belongs to the app; `ojd` only reports it (`design.md` D9).
5. `1209:4A4F` mapping directions need button and axis presses.
6. Settled: no new pid.codes entry (`design.md` Open Questions).
7. Settled: the SDL mapping is not submitted upstream.
8. Turn on GitHub Pages (the user does this).

## 1. Equivalence-test harness

Owns: `Tests/` fixtures and a snapshot of current behavior.
Depends: none.
Verify: `swift test`, `.build/schema-validator/bin/python -m unittest discover -s Tests/RepositoryScripts`.

- [x] 1.1 Snapshot, for every current record, the parsed output of its recorded sample reports as canonical frames. Verify: the snapshot test passes on the unchanged tree with `swift test`.
- [x] 1.2 Snapshot the generated DriverKit match list, the catalog index and the per-record route (extension, raw access, system) as fixture files. Verify: the tests pass on the unchanged tree.
- [x] 1.3 Snapshot the effective SDL mapping text for each persona on the current tree. Verify: the test passes.
- [x] 1.4 Add a helper that compares a refactored build to the snapshots and prints a diff of changed records. Verify: it reports zero diffs now, and one diff after a deliberate local change that is then reverted.

## 2. Generator tables become data (old WP11)

Owns: generator inputs under `Scripts/` and authored inputs for the catalog.
Depends: 1.
Verify: `./Scripts/ojd catalog regenerate --check`, `ruff format --check Scripts Tests/RepositoryScripts`, `ruff check Scripts Tests/RepositoryScripts`, `pyright`, the repository script unit tests.

- [x] 2.1 Move tables hard-coded in the generators (family lists, route lists, name maps) into authored data files. Verify: `./Scripts/ojd catalog regenerate --write` then `--check` give no diff against the 1.2 snapshots.
- [x] 2.2 Remove the duplicate tables from generator code. Verify: `grep` finds none of the moved literals in `Scripts/`, and the unit tests pass.

## 3. ControllerModelID (old WP1)

Owns: the model identifier type and its use in stores.
Depends: 1.
Verify: `swift test`, `swift-format lint --recursive --strict Package.swift Sources Tests`, `swiftlint lint --no-cache --strict`.

- [x] 3.1 Introduce `ControllerModelID` as the key of a record kind of controller. Verify: unit test that two physical units of one model share one ID.
- [x] 3.2 Replace the uses of the overloaded identifier that mean "model". Verify: build passes and 1.1 to 1.3 show zero diffs.
- [x] 3.3 Write the rule that a stored file keeps working or is dropped with no migration (assumption: no migration). Verify: a test loads an old stored file and reports the documented result.

## 4. Session, port and reference (old WP3)

Owns: `ControllerSessionToken`, `ControllerPortKey`, `ControllerReference`, `LogicalControllerID`.
Depends: 3.
Verify: `swift test`, lint pair above.

- [x] 4.1 Add the four types with the naming in `design.md` D12. Verify: unit tests for equality, encoding and uniqueness.
- [x] 4.2 Make `ControllerReference` the only way commands and the endpoint name a controller. Verify: a test resolves a reference by model, unit and logical ID, and refuses an ambiguous one with a catalog error.
- [x] 4.3 Replace session-lifetime uses of the old identifier. Verify: reconnect test keeps the logical ID and changes the token.

## 5. Split DeviceIdentifier (old WP2)

Owns: `ControllerHardwareIdentity`, `ControllerConnectionAddress`.
Depends: 3, 4.
Verify: `swift test`, lint pair.

- [x] 5.1 Split the type into hardware identity and connection address. Verify: build passes; USB and Bluetooth fixtures give equal hardware identity for one model on two links.
- [x] 5.2 Update the USB and HID layers, and the DriverKit host, to the new types. Verify: `./Scripts/ojd check driverkit` and `swift test`.

## 6. DEXT match list from records (old WP10)

Owns: the generated DriverKit match list.
Depends: 2, 5.
Verify: `./Scripts/ojd driverkit generate`, `./Scripts/ojd check driverkit`, `./Scripts/ojd test parsers-macos14`.

- [x] 6.1 Generate the match list from records whose route is `ExtensionOwned`, limited to the seven granted IDs (`045E:02D1`, `02DD`, `02E3`, `02EA`, `0B00`, `0B0A`, `0B12`). Verify: the list matches the 1.2 snapshot and `./Scripts/ojd check driverkit` passes.
- [x] 6.2 Make the signing doctor fail on a match term outside the grant. Verify: a test with an extra ID makes `./Scripts/ojd signing doctor` fail; the real tree passes.
- [x] 6.3 Record the open item about requesting more IDs without changing the list. Verify: `wiki/Known-Issues.md` names the limit.

## 7. Protocol IDs for real sub-protocols (old WP4)

Owns: protocol identifiers in records and parsers.
Depends: 2, 5.
Verify: `swift test`, `./Scripts/ojd test parsers-macos14`, `./Scripts/ojd catalog regenerate --check`.

- [x] 7.1 Give each distinct wire sub-protocol its own protocol ID (for example the GIP variants and the two DS4 report forms). Verify: parser tests name the ID they cover, and 1.1 shows zero diffs.
- [x] 7.2 Reject a record that names an unknown protocol ID with a catalog error. Verify: negative test and `./Scripts/ojd check profiles`.
- [x] 7.3 Move the interface signatures in `ProtocolClassifier.signatures` (XID, XUSB wired and receiver, GIP) into the protocol description data and keep binding devices without a record by them. Verify: `interfaceSignatureBindsWithoutACatalogRecord` and `gipBindsOnlyItsDataInterface` pass unchanged, and no interface triple remains in Swift.

Extras found while closing 7.3 (the protocol descriptions it added had no negative checks):

- [x] 7.4 Make `./Scripts/ojd check schemas` reject bad protocol descriptions: wrong `$schema`, unknown family, a byte out of range, an empty or missing `interfaceSignatures`, an unknown field. Verify: negative unit tests in `Tests/RepositoryScripts` and the authored files still validate.
- [x] 7.5 Limit each family's `variant` in `protocol-description.schema.json` to the variants Swift implements (`xbox.xid` gamepad, `xbox.xusb` wired and receiver, `xbox.gip` usb). Verify: a negative unit test with a variant from another family.
- [x] 7.6 Make `./Scripts/ojd check schemas` fail when a protocol description's file name differs from its `family`, which today fails only when the app starts. Verify: a negative unit test and `./Scripts/ojd check schemas` on the real tree.
- [x] 7.7 Make the Swift loader decode protocol descriptions strictly and testably: reject an unknown field, an unknown `$schema`, a family that differs from the file, and a variant outside the family's `variants`, each with a `ControllerRecordProblem`. Verify: negative tests in `swift test`.
- [x] 7.8 Make `./Scripts/ojd catalog regenerate --check` report a missing, stale or changed protocol copy in the Kit bundle. Verify: unit tests for each case.
- [x] 7.9 Extend 7.5 to every family: `protocol-description.schema.json` admits exactly the variants of `PhysicalProtocolID.variants` per family (including `bluetooth-classic`), and rejects signatures for a family with no variants. Verify: a Swift test keeps the schema equal to `variants` for every family, and per-family negative unit tests in `Tests/RepositoryScripts`.

## 8. Typed parameters replace ControllerQuirk (old WP5)

Owns: typed parameters in records per the D2 table.
Depends: 7.
Verify: `swift test`, `./Scripts/ojd check schemas`, `./Scripts/ojd catalog regenerate --check`.

- [x] 8.1 Replace each `ControllerQuirk` case with a typed parameter or a mode field following the D2 crosswalk. Verify: a test lists every old case and the new place it landed; 1.1 shows zero diffs.
- [x] 8.2 Delete `ControllerQuirk`. Verify: `grep -r ControllerQuirk Sources Tests` returns nothing; build passes.
- [x] 8.3 Update the schema for the new fields. Verify: `./Scripts/ojd check schemas`.

Extras found while closing 8 (the Swift record set merged a patch's `parameters` key by key and could not remove one, while the Python generator replaced them whole). 8.4 settles it: one merge order and one tuning-scope rule shared by the loader, the generator and the fixture.

- [x] 8.4 Introduce the `ControllerPatch` kind (D4: the `controller-override` patch and `defaults` become `ControllerPatch`, `defaults` with `selector.all`) with RFC 7396 merge semantics, `null` deleting a key, the layer order catalog record, built-in patch, package patch, user patch, and the selector order `model`, then `vendorID`/`productID`, then `all` inside one layer. Implement it once in the Swift loader and once in the Python generator. Verify: shared fixture cases run by `swift test` and the repository unit tests give equal effective records, including a `null` delete of a parameter and a user patch beating a package patch.

## 9. Protocol description records (old WP7)

Owns: `ProtocolDescription` kind, with init sequences, report layouts and probes as data.
Depends: 7, 8.
Verify: `swift test`, `./Scripts/ojd check schemas`, `./Scripts/ojd test parsers-macos14`.

- [x] 9.1 Define the `ProtocolDescription` kind and its schema. Verify: sample documents validate; bad ones fail with catalog errors. Done: schema declares `parameters` and `defaults` (capabilities, output rumble and startup writes, input layout, tuning) per family; 11 descriptions; `ProtocolDescription.decode` (Swift) and `validate_protocol_descriptions` (Python) reject with E5002, E5003, E5004.
- [ ] 9.1a Move the family defaults still coded in Swift (`MacOSOwnedOutput.swift`, `DeviceCatalog.swift`, `ProtocolClassifier.swift`, `ControllerProfileCapabilities.swift`, `ControllerTuning+Layers.swift`: rumble intervals, startup writes, capabilities, tuning) into each description's `defaults` and have the drivers read `ProtocolDescription.bundled`. Verify: no copy of a moved default remains in Swift.
- [x] 9.1b The description loader reports a missing or unknown apiVersion as E5001 through `DocumentHeaderProblem` (a wrong kind stays E5002), `validate_schemas.py` agrees, and `ProtocolParameters.violation` reads enum values and ranges from the descriptions.
- [x] 9.1c Express probes as record `modes[]` match keys once a consumer exists; the description schema does not carry probes. Done: `modes[].match.probes` in the record and patch schemas, consumed by mode selection at HID admission; Swift `validateModes` and Python `validate_modes` apply the same rules.
- [x] 9.2 Describe one existing simple protocol as data and run it through the generic interpreter beside the coded parser. Verify: a test shows identical frames from both on the recorded samples. Done: `xbox.xid` carries `defaults.input`, run by `ReportLayoutDriver` (new `table` hats and `symmetric` axes); `XboxXIDDescriptionTests` compares it with `XIDDriver` on the 1.1 characterization steps, which are hand-written transcripts, not hardware captures, plus a per-field sweep of every byte and stick word.
- [ ] 9.3 Describe the remaining protocols whose behavior the data model covers; leave the rest coded and list them. Verify: the list is in `wiki` developer pages and every protocol has a parser test.

## 10. HID usage maps (old WP6)

Owns: usage-to-control maps as data.
Depends: 8, and the vocabulary in 15.
Verify: `swift test`, `./Scripts/ojd check profiles`.

- [ ] 10.1 Move HID usage tables from code into records using canonical control ids. Verify: a test compares each table to the previous output for the recorded samples.
- [ ] 10.2 Support hat, axis and button usages with ranges and dead zones as typed parameters. Verify: unit tests per usage kind.

## 11. Modes and links incl. coreBluetoothGATT (old WP8)

Owns: `modes` and `links` in records, including a Core Bluetooth GATT link kind.
Depends: 9, 5.
Verify: `swift test`, `./Scripts/ojd check schemas`.

- [x] 11.1 Add `modes` (for example XInput, DInput, switch) selected by switch, button combo or probe. Verify: a fixture record with two modes picks each by its probe. Done: probe selection only; `ControllerModeTests` picks each of two modes by its probe. Switch and button-combo selection have no consumer yet.
- [ ] 11.1a Complete `modes` per the `controller-records` "Modes and match keys" requirement: the default mode is a `modes[]` entry, match keys cover link kind, interface signature, manufacturer and product strings and a `bcdDevice` range besides probes, and a mode may set `interface`, `session` and protocol `parameters`. Verify: fixtures for "One model, two modes" (wired versus Bluetooth by link kind) and the `device-matching` "Dongle and wired" scenario.
- [x] 11.2 Add the `coreBluetoothGATT` link kind for BLE controllers. Verify: a mock peripheral test delivers frames through the link.
- [ ] 11.3 Make DS3 over Bluetooth a link of the DS3 record, with the pairing steps as documentation only. Verify: the record validates; hardware check H6 below covers the real pairing.

## 12. ServingRoute and persona records (old WP9)

Owns: `ServingRoute` and `VirtualDevice` kinds; the single serving policy.
Depends: 6, 8, 11.
Verify: `swift test`, `./Scripts/ojd check profiles`, `./Scripts/ojd test parsers-macos14`.

- [ ] 12.1 Define routes (`ExtensionOwned`, raw access, `System`) and the `server` field `system` or `ojd`. Verify: route table test over all records matches the 1.2 snapshot.
- [ ] 12.2 Define `VirtualDevice` records for `Generic` and `SdlCompatible`; `Generic` is the default. Name personas by these ids everywhere (`ojd virtual feed`, `cli-output.schema.json`, `VirtualHIDProfile`) and delete the endpoint's `EndpointPersona.profileName` mapping to `hid-generic`/`hid-xbox-one-s-bt`. Verify: a test checks the default and that the opt-in switches the persona without replug.
- [ ] 12.3 Put route and persona choice in one policy that the service, CLI, GUI and endpoint all call. Verify: a test shows the four callers get the same answer for a fixture set.
- [ ] 12.4 Add `ojd controller claim <ref>` and `ojd controller release <ref>` and remove `controller ownership`. Verify: CLI tests for success, `--dry-run`, `--json`, and the refusal `error.E2023` for raw-USB routes.
- [ ] 12.5 Keep stick-report delivery semantics (newest state within one send time, every button edge). Verify: the existing delivery tests pass for both personas.

## 13. Same-ID clone probes (old WP12)

Owns: probe rules in device matching.
Depends: 11, 12.
Verify: `swift test`, `./Scripts/ojd check profiles`. Hardware: H4.

- [x] 13.1 Add record-level probes to tell clones with the same VID:PID from the genuine device. Verify: a mock test chooses each record from different probe replies. Done: `ScriptedProbeReader` replies select different modes of one record; probe reads are bounded at 2 s with one outstanding read per connection.
- [x] 13.2 Encode the DS3 0xEF discriminator as a probe. Verify: unit test; final location mapping waits on open item 1. Done: `054c-0268.patch.json` mode `feature-ef-answers` (0xEF, length 49 chosen, not recorded); answer selects it, a stall gives `noModeMatched`. It runs the same `sony.sixaxis` protocol, so it is inert until open item 1.
- [x] 13.3 Define the fallback when a probe gets no reply. Verify: test shows the documented fallback and a log line. Done: a timeout, busy or other non-stall failure is inconclusive; selection logs a line and keeps the default mode, as `wiki/Controller-Records.md` says.

## 14. Schemas: flat layout, header, Pages-ready ids

Owns: `Resources/Schemas/`, `Scripts/` validators, `Resources/Schemas/AGENTS.md`.
Depends: 9, 12.
Verify: `./Scripts/ojd check schemas`, `.build/schema-validator/bin/python -m unittest discover -s Tests/RepositoryScripts`, `ruff check Scripts Tests/RepositoryScripts`, `pyright`.

- [x] 14.1 Move schemas from `Resources/Schemas/v1beta1/` to flat files named `<kind>.schema.json`. Verify: `./Scripts/ojd check schemas` finds all and nothing remains in the old directory.
- [x] 14.2 Require `apiVersion: openjoystickdriver/v1alpha1` and `kind` on every document kind; reject `openjoystickdriver.io/v1beta1`. Verify: negative tests per kind.
- [x] 14.3 Set `$id` to `https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha1/<kind>.schema.json` and extend `validate_schemas` to check ids and the `apiVersion` constant against one source. Verify: the constant-equality unit test.
- [x] 14.4 Rewrite `Resources/Schemas/AGENTS.md` for the flat layout. Verify: markdownlint over the file.
- [x] 14.5 Update every sample and doc under `docs/sdk/` to the new header. Verify: `./Scripts/ojd check schemas` and `ojd mod validate` on the sample.

## 15. Control vocabulary unification

Owns: canonical control ids and the crosswalk.
Depends: 8, 14.
Verify: `swift test`, `./Scripts/ojd check profiles`, `./Scripts/ojd catalog regenerate --check`.

- [ ] 15.1 Adopt the UpperCamelCase ids (`South`, `East`, ...) across records, profiles, the endpoint and the GUI. Verify: a test maps every old name to a new id with none left over.
- [ ] 15.2 Keep one crosswalk to SDL and to the system HID names. Verify: round trip test per control.
- [ ] 15.3 Update stored profile loading for renamed controls (rejected as in 3.3 if not valid). Verify: negative test.

## 16. SDL mapping, export and launch environment

Owns: mapping generation, `ojd virtual export-mapping`, environment for launched apps.
Depends: 12, 15.
Verify: `swift test`, `./Scripts/ojd check profiles`. Hardware: H5, H7.

- [ ] 16.1 Generate the SDL mapping string for each persona from records. Verify: matches 1.3 where the persona is unchanged; new fields tested.
- [ ] 16.2 Add `ojd virtual export-mapping`. Verify: CLI test and `--json` envelope validation.
- [ ] 16.3 Add the environment (for example the SDL hints variable) for apps launched by OJD. Verify: a test launches a helper that prints its environment.
- [ ] 16.4 Fix the `02FD` persona only with hardware evidence from H5. Verify: record the evidence; otherwise leave unchanged and list it.
- [ ] 16.5 Keep the Wine, CrossOver and browser rows as expectations until H7 confirms them. Verify: `wiki` says "expected" until then.

## 17. CLI vocabulary, command tree, settings, neutral core

Owns: `Sources/OpenJoystickDriverCLI`, settings schema, `DataDirectory` port, core split.
Depends: 4, 12, 14.
Verify: `swift test`, lint pair, `./Scripts/ojd check schemas`.

- [ ] 17.1 Rename commands and words by the D9 table, and give the access values OS-neutral names (`ioHID`, `ioUSBHost`, `usbDriverKit`, `coreBluetoothGATT` in `report.schema.json` and `DeviceAccessBackend`), with OS words only under `platform` (cli-surface). Verify: a test lists every old word as rejected with a hint to the new word.
- [ ] 17.2 Add a settings schema and move settings out of `UserDefaults` into layered files; add `ojd setting` keys for every GUI-only switch. Verify: schema check and a round-trip test.
- [ ] 17.2a Add the `setting` keys for show in menu bar and update checks together with their switches in the 20.x General pane, and give Send Test Notification a CLI place once a service-to-GUI notification path exists (D9). Verify: the 17.2 round-trip test covers the new keys; the D10 coverage test lists Send Test Notification.
- [x] 17.3 Add the single `DataDirectory` port used by every store. Verify: `grep` finds no direct path building outside the port; tests use a temp directory.
- [ ] 17.4 Split the neutral core from a macOS host adapter so `Sources/OpenJoystickDriver` has no macOS-only imports outside `platform`. Verify: a script or test greps imports and fails on a violation.
- [ ] 17.5 Add the coverage test that lists every command and flags any with no GUI place. Verify: the test passes and fails on a fake command.
- [x] 17.6 Decide on the command-line-tool symlink after open item 4. Verify: the decision is in `design.md`.
- [ ] 17.6a Make `ojd status` report whether the command-line tool link is installed, and give `ojd` no command or setting that installs or removes it (D9). Verify: CLI tests for an installed, a missing and a broken link, with `--json`.

## 18. SDK endpoint and reference client

Owns: endpoint, `endpoint.schema.json`, reference client, `docs/sdk/`.
Depends: 4, 14, 17.
Verify: `swift test`, `./Scripts/ojd check schemas`.

- [x] 18.1 Implement Challenge, Hello, Welcome, Subscription, FeedRequest, FeedSession, Frame and Status with `AccessGrants`. Verify: round-trip tests against the schema.
- [x] 18.2 Return the supported-version list on a bad `apiVersion`, wrong kind or missing header, with new catalog codes. Verify: tests for each; old codes keep numbers.
- [ ] 18.3 Ship the reference client and its test. Verify: the test subscribes and receives a frame.
- [ ] 18.4 Document the endpoint in `docs/sdk/`. Verify: markdownlint.

## 19. Streaming boundary and WebRTC

Owns: `InputSource`, `OutputSink`, queue policy, WebRTC transport, latency report.
Depends: 12, 18.
Verify: `swift test`, lint pair. Hardware: H10.

- [ ] 19.1 Introduce `InputSource` and `OutputSink` and attach physical, virtual, endpoint paths to them. Verify: 1.1 shows zero diffs.
- [ ] 19.2 Add bounded queue policy per record or default. Verify: slow-consumer test keeps memory bounded and delivers the newest frame.
- [x] 19.3 Add per-stage timestamps to `ojd diagnose`. Verify: test output lists dispatch and delivery times. Done: read, parse, dispatch, delivery-virtual-device and delivery-endpoint stamps; `DeviceManagerFrameTimingsTests` asserts all five in order and `--plain` adds one timing row per stage.
- [ ] 19.4 Add the WebRTC transport, off by default, using the endpoint Subscription flow for signalling. Verify: loopback test; with the setting off, a socket scan shows no listener.

## 20. AppKit GUI shell

Owns: the app target, six areas, 13 screen groups.
Depends: 17, 18.
Verify: `swift test`, lint pair, `python3 Scripts/Quality/check_swift_file_length.py`.

- [ ] 20.1 Build the shell: sidebar with six areas (Command-1 to Command-6), toolbar, detail panes. Verify: UI-free tests for the area model; manual launch.
- [ ] 20.2 Build the 13 screen groups one at a time. Each ends with a `/impeccable` pass and a gate where the user approves the visuals before the next group. Verify: user approval recorded per group in this file.
- [ ] 20.3 Put every CLI action in the GUI per the coverage matrix in `design.md`. Verify: the 17.5 coverage test passes with no gaps.
- [ ] 20.4 Add accessibility labels (`a11y.` keys) for every control. Verify: an audit script or test lists unlabeled controls and finds none.

## 21. Menu bar and main menu

Owns: status item and main menu.
Depends: 20.
Verify: `swift test`, lint pair.

- [ ] 21.1 Build the fixed status-item layout; disabled, not hidden. Verify: model test of item states for no-controller, one wireless controller, and error.
- [ ] 21.2 Update from service notifications; keep polling only as fallback. Verify: test that a notification updates within one second.
- [ ] 21.3 Build the main menu set with File, Edit, View, Controller, Profile, Window and Help items. Verify: test that every item has an action and a GUI counterpart.
- [ ] 21.4 Build the status line from one localized format string. Verify: unit test with `ar-SA`.

## 22. Localization re-key, Crowdin, checker

Owns: `*.lproj`, `crowdin.yml`, `Scripts/Quality/check_localization_keys.py`, `LOCALIZATION.md`.
Depends: 17, 20, 21.
Verify: `python3 Scripts/Quality/check_localization_keys.py`, `ruff check Scripts Tests/RepositoryScripts`, `pyright`.

- [ ] 22.1 Write the old-to-new key map by the namespaces in `localization-keys`. Verify: map covers every current key.
- [ ] 22.2 Apply the re-key mechanically to the 22 bundles. Verify: the value comparison test shows identical values except merged duplicates and positional specifiers.
- [ ] 22.3 Add positional specifiers, `.stringsdict` plurals and translator comments to `en-US`. Verify: checker passes.
- [ ] 22.4 Update the checker for namespaces, OS words, specifiers, comments. Verify: negative unit tests per rule.
- [ ] 22.5 Add `crowdin.yml` and stop copying `Localizable.template.*` into bundles. Verify: a test parses the file; build output has no template.
- [x] 22.6 Review translation decisions from open item 3 as separate edits. Verify: each decision is a separate commit with the user's answer. Done: the user delegated the choices on 2026-10-15; eight `fix(l10n)` commits, one per decision.
- [ ] 22.7 Update `LOCALIZATION.md`. Verify: markdownlint.

## 23. Docs, wiki, CHANGELOG, release checks

Owns: `wiki/`, `docs/`, `CHANGELOG.md`, `CONTRIBUTING.md`.
Depends: all above.
Verify: the full check list.

- [ ] 23.1 Rewrite wiki pages for the new vocabulary, including fixing stale lines in `wire-protocols.md` (lines 20 and 22), `source-topology.md` and `Using-the-App.md` (line 160). Verify: `grep` for old words finds none; markdownlint.
- [ ] 23.2 Add the CHANGELOG lines for each breaking item, rejected document shapes, the new default persona and the removed CLI words. Verify: a review against the BREAKING marks in `proposal.md`.
- [ ] 23.3 Apply `pending-deltas.md` after the old change is archived. Verify: `openspec validate platform-neutral-redesign --strict`.
- [ ] 23.4 Run the full check list on the final tree, plus `./Scripts/ojd test parsers-macos14`. Verify: every command exits 0; paste the results.

## Hardware checks (maintainer)

These need the maintainer and a device. Each result is recorded in `wiki` or the record's evidence field.

- [ ] H1 Wolverine V1 TE: connect, confirm frames, route and persona.
- [ ] H2 GameSir G7 SE `3537:1010`: confirm the record and route.
- [ ] H3 DS3 CECHZC2E genuine and a DS3 clone: confirm the 0xEF discriminator and settle open item 1.
- [ ] H4 DS4 v2: confirm the report form and probe.
- [ ] H5 8BitDo `2DC8:301B` and the `02FD` persona: SDL3 or Steam shows the right mapping.
- [ ] H6 A1398 on macOS 12 (floor) and DS3 Bluetooth pairing.
- [ ] H7 Wine, CrossOver and a browser: confirm the expectations in the SDL consumer table.
- [ ] H8 SDL3 and Steam with `Generic` and `SdlCompatible`.
- [ ] H9 `1209:4A4F`: press each button and move each axis to confirm mapping directions (open item 5).
- [ ] H10 Stutter: measure with the 19.3 timestamps, with WebRTC off and on.

## Workflow follow-up

- Push, tag, notarize and publish are the maintainer's actions and need confirmation.
- Turn on GitHub Pages so the schema `$id` URLs resolve (open item 8).
- Archive this change after `release-0-6-0-alpha-1` is archived, then convert `pending-deltas.md` into MODIFIED and REMOVED deltas.
