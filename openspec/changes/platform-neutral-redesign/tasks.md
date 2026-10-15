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
  - `swift-format lint --recursive --strict Package.swift Sources Tests Tools`
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
Verify: `swift test`, `swift-format lint --recursive --strict Package.swift Sources Tests Tools`, `swiftlint lint --no-cache --strict`.

- [x] 3.1 Introduce `ControllerModelID` as the key of a record kind of controller. Verify: unit test that two physical units of one model share one ID.
- [x] 3.2 Replace the uses of the overloaded identifier that mean "model". Verify: build passes and 1.1 to 1.3 show zero diffs.
- [x] 3.3 Write the rule that a stored file keeps working or is dropped with no migration (assumption: no migration). Verify: a test loads a file without the supported `apiVersion` and gets the unsupported-version error.

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
- [ ] 9.1a Move the family defaults still coded in Swift (`MacOSOwnedOutput.swift`, `DeviceCatalog.swift`, `ProtocolClassifier.swift`, `ControllerProfileCapabilities.swift`, `ControllerTuning+Layers.swift`: rumble intervals, startup writes, capabilities, tuning) into each description's `defaults` and have the drivers read `ProtocolDescription.bundled`. Verify: no copy of a moved default remains in Swift. Startup writes, CRC seed, `usbTransferTimeoutMs` and `frameQueueCapacity` are done; the rest is 9.1d to 9.1i.
- [x] 9.1b The description loader reports a missing or unknown apiVersion as E5001 through `DocumentHeaderProblem` (a wrong kind stays E5002), `validate_schemas.py` agrees, and `ProtocolParameters.violation` reads enum values and ranges from the descriptions.
- [x] 9.1c Express probes as record `modes[]` match keys once a consumer exists; the description schema does not carry probes. Done: `modes[].match.probes` in the record and patch schemas, consumed by mode selection at HID admission; Swift `validateModes` and Python `validate_modes` apply the same rules.
- [x] 9.1d Keep-alive writes become description data as `defaults.output.keepAlive` (interval, payload, optional seed) for GameSir, GIP, Switch 2 and Steam Deck/Triton; the drivers read them and the duplicate `gameSirEnhancedHIDHeartbeatPayload` goes. Verify: the schema, Swift decoder and Python validator accept and reject the same documents; a driver test shows each family's keep-alive bytes and interval unchanged. Done: keep-alive lives in `defaults.session.keepAlive` of each description, read by `DriverSessionPlan` (`keepAliveChannels` and one interval, no `0` placeholders); the unused record key `keepAliveIntervalMs` is removed and rejected in the schema, Swift and Python; Switch 2 rumble keep-alive and Triton rumble resend stay coded, listed under "Coded Behavior" in `docs/development/wire-protocols.md`; the Swift decoder now rejects a keep-alive on `xbox.xid` like the schema.
- [x] 9.1e Switch 1 subcommands and calibration reads become description data: the rolling counter rule and the request list. Verify: a test shows the same subcommand bytes, in order, as before the move; 1.1 shows zero diffs. After 9.1d (same schema and generator). Done: subcommands and SPI calibration reads are `defaults.session.subcommands` in `nintendo.switch1.json` with the counter rule `counterModulus` 16, run by `SubcommandPlan` and checked by Python `subcommand_violations`; `Switch1SubcommandBytesTests` pins the bytes and order; snapshots show no diffs. The player indicator and the 0x10 rumble report are left for 11.4. `swift test` passed with `PhysicalOutputExecutorTests` skipped, which hangs independently (24.17).
- [ ] 9.1f GIP named packets (`GIPStartupPacket`) become description data. Verify: a test shows the same packet bytes and sequence numbers as before the move; 1.1 shows zero diffs. After 9.1e.
- [ ] 9.1g The remaining limits coded in drivers (`gipHandshakeMaxAttempts`, `gipAnnounceResendLimit`, `xbox360ReceiverInquiryResendLimit`, `xbox360OutputTimeoutMs`) become tuning keys or description fields with their defaults in the descriptions. Verify: Swift and Python range checks agree; a test reads each value from the description. After 9.1f (same GIP driver and `xbox.gip.json`).
- [ ] 9.1h Structural family facts move from code to the descriptions or the generator's authored inputs: `PhysicalProtocolID.variants` and `storesVariant`, the capability sets, the per-family variant enums, the tuning-key scope rules in `controller.schema.json`, and the family table in `generate_xpad_records.py`. Verify: one source per fact, read by Swift and Python; `catalog regenerate --check` passes with no record change.
- [ ] 9.1i Fixtures follow the moved defaults: `Tests/RepositoryScripts/fixtures/controller_patch/cases.json` and `ProtocolDescriptionDriverTimingTests.swift` cover `usbTransferTimeoutMs` (range 1...60000, default 2000) in place of `gipRumbleTransferTimeoutMs`. Verify: the new cases pass in Swift and Python and a removed key is rejected.
- [x] 9.2 Describe one existing simple protocol as data and run it through the generic interpreter beside the coded parser. Verify: a test shows identical frames from both on the recorded samples. Done: `xbox.xid` carries `defaults.input`, run by `ReportLayoutDriver` (new `table` hats and `symmetric` axes); `XboxXIDDescriptionTests` compares it with `XIDDriver` on the 1.1 characterization steps, which are hand-written transcripts, not hardware captures, plus a per-field sweep of every byte and stick word.
- [ ] 9.3 Describe the remaining protocols whose behavior the data model covers; leave the rest coded and list them. Verify: the list is in `wiki` developer pages and every protocol has a parser test.

## 10. HID usage maps (old WP6)

Owns: usage-to-control maps as data.
Depends: 8, and the vocabulary in 15.
Verify: `swift test`, `./Scripts/ojd check profiles`.

- [x] 10.1 Move HID usage tables from code into records using canonical control ids. Verify: a test compares each table to the previous output for the recorded samples. Done: `HIDUsageLayoutEquivalenceTests` compares against the golden `Tests/HIDUsageGolden/hid-usage-layouts.txt`, generated from the coded tables at 36bf3332; maps live in `input.hidUsageMap` of records 11c1-5600, 2e95-434d, 2dc8-301b/301c, patch 0079-0006, and the `hid.descriptor.json` defaults.
- [x] 10.2 Support hat, axis and button usages with ranges and dead zones as typed parameters. Verify: unit tests per usage kind. Done: `HIDUsageMapTests` and `test_hid_usage_map_schema.py`.

## 11. Modes and links incl. coreBluetoothGATT (old WP8)

Owns: `modes` and `links` in records, including a Core Bluetooth GATT link kind.
Depends: 9, 5.
Verify: `swift test`, `./Scripts/ojd check schemas`.

- [x] 11.1 Add `modes` (for example XInput, DInput, switch) selected by switch, button combo or probe. Verify: a fixture record with two modes picks each by its probe. Done: probe selection only; `ControllerModeTests` picks each of two modes by its probe. Switch and button-combo selection have no consumer yet.
- [ ] 11.1a Complete `modes` per the `controller-records` "Modes and match keys" requirement: the default mode is a `modes[]` entry, match keys cover link kind, interface signature, manufacturer and product strings and a `bcdDevice` range besides probes, and a mode may set `interface`, `session` and protocol `parameters`. Verify: fixtures for "One model, two modes" (wired versus Bluetooth by link kind) and the `device-matching` "Dongle and wired" scenario.
- [x] 11.2 Add the `coreBluetoothGATT` link kind for BLE controllers. Verify: a mock peripheral test delivers frames through the link.
- [ ] 11.3 Make DS3 over Bluetooth a link of the DS3 record, with the pairing steps as documentation only. Verify: the record validates; hardware check H6 below covers the real pairing.
- [ ] 11.4 Implement the "Sessions as data" requirement with one `session` shape used by a description's `defaults`, a record's `default` mode and every other mode: `startup` (init), `keepAlive`, `settle`, `shutdown`, vendor control transfers (`bmRequestType`, `bRequest`, `wValue`, `wIndex`, `wLength`) gated by match keys, and output templates (fixed bytes, scaling, motor positions, resend interval). The record-level `output.startup` and the description's `defaults.output.startup` move into it with no alias. After 9.1f, so the moved family data lands in this shape. Verify: the spec's "Gated vendor reads" and "Byte format" scenarios as Swift and Python tests; 1.1 shows zero diffs.
- [ ] 11.5 Match `interfaceSignature` on the endpoint set too (design D7), not only the class triple and HID usage. Verify: a fixture with the same class triple and a different endpoint set selects a different mode, in Swift and Python.
- [ ] 11.6 Report the `proprietary-radio-receiver` link kind from real discovery (for example from the receiver's record), so a mode can match it outside fixtures. Verify: a discovery test of a receiver reports the link and selects the matching mode.
- [ ] 11.7 Make Swift `StartupWrite.transport` accept only the schema's transports (usb, bluetooth-classic, bluetooth-le), and move the `2563:0523` Sixaxis clone's Bluetooth startup write into a `bluetooth` mode session like `054c:0268`. Verify: a Swift decoder test rejects another transport as the schema does; the clone record validates and selects the mode by link.

## 12. ServingRoute and persona records (old WP9)

Owns: `ServingRoute` and `VirtualDevice` kinds; the single serving policy.
Depends: 6, 8, 11.
Verify: `swift test`, `./Scripts/ojd check profiles`, `./Scripts/ojd test parsers-macos14`.

- [x] 12.1 Define routes (`ExtensionOwned`, raw access, `System`) and the `server` field `system` or `ojd`. Verify: route table test over all records matches the 1.2 snapshot. Done: records carry `server` (`system` or `ojd`) and an access route; `recordRoutesMatchSnapshot` checks the route table of every record against the `record-routes` snapshot.
- [x] 12.2 Define `VirtualDevice` records for `Generic` and `SdlCompatible`; `Generic` is the default. Name personas by these ids everywhere, with the kebab-case forms `generic` and `sdl-compatible` on the command line (`ojd virtual feed`, `cli-output.schema.json`, `VirtualHIDProfile`) and delete the endpoint's `EndpointPersona.profileName` mapping to `hid-generic`/`hid-xbox-one-s-bt`. Verify: a test checks the default and that the opt-in switches the persona without replug. Done: `virtual-device.generic.json` and `virtual-device.sdl-compatible.json` under `virtual-device.schema.json`; `EndpointPersona.profileName` is gone; tests cover the `Generic` default and the opt-in retargeting without replug; Python `test_virtual_device_schema.py` rejects bad headers, ids and members.
- [x] 12.3 Put route and persona choice in one policy that the service, CLI, GUI and endpoint all call. Verify: a test shows the four callers get the same answer for a fixture set. Done: `ServingPolicy` is the only caller of the profile selector; `theServiceDescriptionTheWatchStreamServesTheCLIAndTheGUIAnswerWhatThePolicyDecided` runs a fixture set through the service description (which the endpoint's watch stream serves), the CLI and the GUI. The per-app input was dropped from the spec: macOS does not say which app reads a virtual HID device.
- [x] 12.4 Add `ojd controller claim <ref>` and `ojd controller release <ref>` and remove `controller ownership`. Verify: CLI tests for success, `--dry-run`, `--json`, and the refusal `error.E2023` for raw-USB routes. Done: `controller claim`/`release` replace `controller ownership`; the server picker is `setControllerServer` with `ControllerServer*` payloads and GUI `ControllerServerPicker`; CLI tests cover success, `--dry-run`, `--json` and E2023; all 21 commands pass on `682279d8`.
- [x] 12.5 Keep stick-report delivery semantics (newest state within one send time, every button edge). Verify: the existing delivery tests pass for both personas. Done: the stick-delivery tests run for both personas (`Generic` and `SdlCompatible`) and pass.

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

- [ ] 15.1 Adopt the UpperCamelCase ids (`South`, `East`, ...) across records, profiles, the endpoint and the GUI. Verify: `rg` finds no old control name in Sources, Tests, Tools, Scripts or Resources, and no test or table maps old names. Done: `Resources/Schemas/vocabulary.schema.json` and the Swift `Control` enum hold the UpperCamelCase ids, with the six touch and trackpad ids; records, protocol descriptions, profiles, `RemappingButton`/`RemappingAxis`, steering outputs, the endpoint and bridge use them; `ControlVocabularyTests` maps every old name with none left over; PlayStation Share/Create now map to the Back bit (one `buttonBit`); all 22 commands pass on `ca9f1e52`. Reopened: `ControlVocabularyTests` keeps an old-name map; this closes with 24.19.
- [x] 15.2 Keep one crosswalk to SDL and to the system HID names. Verify: round trip test per control. Done: `Resources/Vocabulary/crosswalk.json` has one row per control (SDL, evdev, Apple, HID, W3C), documentation only; `ControlVocabularyTests` and `test_control_vocabulary.py` round-trip every control; cell sources are confirmed in 15.6.
- [x] 15.3 Update stored profile loading for renamed controls (rejected as in 3.3 if not valid). Verify: negative test. Done: profiles with removed names (`south`, `face-south`, `share`, `options`, `left_trigger_click`, `view`) load as `.damagedProfile` with bytes unchanged (`ProfileLibraryTests+Recovery`, `ProfileSchemaTests`).
- [x] 15.4 Make Y axes positive down everywhere a value leaves or enters OJD (records, profiles, the endpoint Frame, CLI output, localization text) and in the internal `StickPosition`, so one convention holds. Verify: a test per surface pushes the stick up and reads a negative Y; 1.1 shows the parsed frames with the sign recorded once. Done: canonical stick Y is positive down end to end with one negation at parse for raw-Y-up drivers; stick pointer, aim, flick, scroll, steering and gyro-stick paths treat negative Y as up (`StickYDirectionTests`); `axis:LeftStickY:negative` keeps its physical meaning; snapshot Y-row labels only. On `b6f19152` 21 of 22 commands pass; `swift test` hit one `StartupLifetimeTests` load flake (5 of 5 isolated runs pass), tracked as 24.22.
- [ ] 15.5 Move the names that 15.1 left on the old kind onto the vocabulary: D-pad direction names, the endpoint Frame `dpad` list, gyro and steering enum values, the `axis_direction` enum, and profile keyboard outputs as W3C `KeyboardEvent.code` values. Verify: a test per kind rejects the old name; Swift and Python agree.
- [ ] 15.6 Confirm each crosswalk cell against its source (HID Usage Tables, Apple GameController docs, SDL3 and Linux headers) and record the source per column; the wiki table is generated from `Resources/Vocabulary/crosswalk.json`. Verify: a test compares the wiki table with the JSON.
- [ ] 15.7 Remove the label plumbing (`ControllerButtonLabels`) that 15.1 left without a use, after confirming each use is gone, and derive the WebRTC bridge's `PeerMessage` button list from `vocabulary.schema.json` (or a test that compares them). Verify: the build passes with the plumbing gone; a test fails if the lists differ.

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

- [ ] 17.1 Rename commands and words by the D9 table (cli-surface), with OS words only under `platform`; done when 17.1a to 17.1d are done. Verify: each part's old words fail as unknown words with no hint, and no code, test or string lists them.
- [ ] 17.1a `extension` command to `transport-extension`, kind `DriverExtension` to `TransportExtension`, `usbExtension claims|doesNotClaim` to `transportClaim claimed|unclaimed`, `ownership.physical` `driverKitOwnedUSB`/`nativeGamepad`/`nativeHIDVisible` to `ExtensionOwnedUsb`/`SystemGamepad`/`SystemHidVisible`, and the GUI coverage matrix key `extension` to `transport-extension`. Verify: a test shows each old word of its rows fails with the same error as any unknown word and no hint; `rg` finds none of the old words in Sources, Tests, Tools, Scripts or Resources. Done: `ojd transport-extension`, kind `TransportExtension`, `transportClaim claimed|unclaimed`, `ExtensionOwnedUsb`/`SystemGamepad`/`SystemHidVisible`, `status --json` `transportExtension`, check ids `transport-extension-*` and snapshot labels `transport-extension`; old words are rejected with hints from the single `RenamedWord.all` (`ExtensionWordsTests`, `test_extension_words_schema.py`, `test_renamed_words.py`); kept: macOS display text and internal `Extension*` type names. All 22 commands pass on `e7a4dc17` (command 22 with `--skip PhysicalOutputExecutorTests` until 24.17 merges). Reopened: the hint layer (`RenamedWord`, `RenamedFlags`, E5006) breaks decision 13; this closes with 24.19.
- [ ] 17.1b Permission ids `input-monitoring`/`accessibility`/`driver-extension` to `input-read`/`input-inject`/`usb-transport`, `identityKind team|apple` and `teamIdentifier` to `publisher.kind signed|platform` and `publisher.id`, `--app <bundle-id>` and `bundleIdentifier` to `--app <app-id>` and `appID`, modifiers `command`/`option` to `meta`/`alt`. Verify: a test shows each old word of its rows fails with the same error as any unknown word and no hint; `rg` finds none of the old words in Sources, Tests, Tools, Scripts or Resources. Done: permission ids, `publisher {kind,id}` with the single `CodeSigningIdentity.Kind` (`adHoc` only), `--app`/`appID`, `meta`/`alt` and `frontmostAppID`; old words and stored old `AccessGrants.json` are rejected with hints (E5006, else E5005, no migration); every `AccessGrantStoreError` case has a code (E2024-E2032, E5007) and localized text (`AccessGrantStoreErrorTests`, `AccessWordsTests`, `test_access_words_schema.py`); OS API names stay. All 22 commands pass on `e7a4dc17` (command 22 with `--skip PhysicalOutputExecutorTests` until 24.17 merges). Reopened: the hint layer (`RenamedWord`, `RenamedFlags`, E5006) breaks decision 13; this closes with 24.19.
- [ ] 17.1c `diagnose --bundle` to `diagnose --output`, `macOSVersion` to `osVersion` plus `osName`, `appleGameControllerAudit`/`appleExactDeviceCount`/`appleRecord`/`appleIdentifiers` to `systemGamepadAudit`/`systemExactDeviceCount`/`systemRecord`/`systemIdentifiers`. Verify: a test shows each old word of its rows fails with the same error as any unknown word and no hint; `rg` finds none of the old words in Sources, Tests, Tools, Scripts or Resources. Done: `diagnose --output` (`--bundle` refused with a hint), `osVersion` plus `osName`, `systemGamepadAudit`/`systemExactDeviceCount`/`systemRecord`/`systemIdentifiers`, `skippedSystemDeviceCount` and the `SystemGamepad*` audit types; old words are rejected with hints from `RenamedWord.all` (`.documentField(in:)` rows, `test_renamed_words.py`). All 22 commands pass on `e7a4dc17` (command 22 with `--skip PhysicalOutputExecutorTests` until 24.17 merges). Reopened: the hint layer (`RenamedWord`, `RenamedFlags`, E5006) breaks decision 13; this closes with 24.19.
- [ ] 17.1d Access backends `ioHID`/`ioUSBHost`/`usbDriverKit`/`coreBluetoothGATT` to `hid`/`rawUsb`/`usbExtension`/`gatt` in `report.schema.json` and `DeviceAccessBackend`, kinds `USBPacket`/`JoyConPair` to `RawReport`/`ControllerPair`, the socket in `DARWIN_USER_TEMP_DIR` behind the runtime-directory port, and endpoint `as: SdlCompatible` to persona ids. Verify: a test shows each old word of its rows fails with the same error as any unknown word and no hint; `rg` finds none of the old words in Sources, Tests, Tools, Scripts or Resources.
- [x] 17.2 Add a settings schema and move settings out of `UserDefaults` into layered files; add `ojd setting` keys for every GUI-only switch. Verify: schema check and a round-trip test. Done: `settings.schema.json`, layered files with a one-time `UserDefaults` import; `everySettingRoundTripsThroughTheUserFile` and `./Scripts/ojd check schemas` pass. Show in menu bar, update checks and Send Test Notification stay with 17.2a.
- [ ] 17.2a Add the `setting` keys for show in menu bar and update checks together with their switches in the 20.x General pane, and give Send Test Notification a CLI place once a service-to-GUI notification path exists (D9). Verify: the 17.2 round-trip test covers the new keys; the D10 coverage test lists Send Test Notification.
- [x] 17.3 Add the single `DataDirectory` port used by every store. Verify: `grep` finds no direct path building outside the port; tests use a temp directory.
- [x] 17.4 Split the neutral core from a macOS host adapter so `Sources/OpenJoystickDriver` has no macOS-only imports outside `platform`. Verify: a script or test greps imports and fails on a violation. Done: `Scripts/Quality/check_neutral_core_imports.py` checks imports against an allow-list (string literals and interpolations lexed, covered by `test_neutral_core_imports.py`), runs in the hook, the check lists and CI; the CLI tests use `FakePlatformHost` instead of the macOS host target.
- [ ] 17.4a Move the macOS-only code out of `OpenJoystickDriverKit` (IOKit HID streams and sessions, the user-space virtual-device dispatcher, GameController synthetic HID, Bluetooth LE routing, access control, mode probe; 21 files) into platform targets behind Kit protocols, so the core the CLI depends on is platform-neutral. Verify: the neutral-core import check covers `Sources/OpenJoystickDriverKit` and passes, with a planted violation in Kit failing it.
- [x] 17.5 Add the coverage test that lists every command and flags any with no GUI place. Verify: the test passes and fails on a fake command. Done: `GUICoverageTests` (`everyCommandOfTheRealTreeHasAGUIPlace`, `everyMatrixEntryNamesARealCommand`, `aFakeCommandWithNoGUIPlaceIsReported`) over `GUICoverageMatrix.swift`.
- [x] 17.6 Decide on the command-line-tool symlink after open item 4. Verify: the decision is in `design.md`.
- [x] 17.6a Make `ojd status` report whether the command-line tool link is installed, and give `ojd` no command or setting that installs or removes it (D9). Verify: CLI tests for an installed, a missing and a broken link, with `--json`. Done: `StatusCommandLinkTests` covers installed, missing, broken and relative links, each with `--json`.

## 18. SDK endpoint and reference client

Owns: endpoint, `endpoint.schema.json`, reference client, `docs/sdk/`.
Depends: 4, 14, 17.
Verify: `swift test`, `./Scripts/ojd check schemas`.

- [x] 18.1 Implement Challenge, Hello, Welcome, Subscription, FeedRequest, FeedSession, Frame and Status with `AccessGrants`. Verify: round-trip tests against the schema.
- [x] 18.2 Return the supported-version list on a bad `apiVersion`, wrong kind or missing header, with new catalog codes. Verify: tests for each; old codes keep numbers.
- [x] 18.3 Ship the reference client and its test. Verify: the test subscribes and receives a watch line with the controller's input state. Done: `Scripts/SDK/reference_client.py`; `theClientSubscribesAndReceivesAControllerFrame` and `test_endpoint_reference_client.py` pass. The service sends watch lines on subscribe; `Frame` is a client-to-service kind.
- [x] 18.4 Document the endpoint in `docs/sdk/`. Verify: markdownlint. Done: `docs/sdk/endpoint.md`; markdownlint reports 0 issues over 140 files and `test_sdk_docs.py` checks the examples against the catalog and fixtures.

## 19. Streaming boundary and WebRTC

Owns: `InputSource`, `OutputSink`, queue policy, WebRTC bridge, latency report.
Depends: 12, 18.
Verify: `swift test`, lint pair. Hardware: H10.

- [x] 19.1 Introduce `InputSource` and `OutputSink` and attach physical, virtual, endpoint paths to them. Verify: 1.1 shows zero diffs. Done: `Streaming/StreamBoundary.swift` defines `InputSource`, `OutputSink` and `StreamFrame`; `DevicePipeline`, the feed registry's sessions and `EndpointStreamSource` are sources; every `OutputDispatcher`, `VirtualFeedDeviceSink`, `EndpointSubscribers` and `DeviceManager` are sinks; `StreamBoundaryTests` and the equivalence snapshots pass with no snapshot change. The remaining paths are 19.1a.
- [x] 19.1a Put the remaining paths on the boundary: the host-feedback return to endpoint feed clients through `OutputSink.consume(command:)` (an async-capable return in place of the locked `FeedExchanger` send), the client-to-registry hop in `EndpointServer+Feed`, and `activateOutput`, `RemappingRoutingCore` and `RemappingPhysicalOutputBridge` dispatch. Verify: no service path calls a dispatcher outside a sink (a test or check), Service tests for `VirtualFeedDeviceSink`, the session origins and the `EndpointSubscribers` generation guard, and 1.1 shows zero diffs. Done: host feedback, the client-to-registry hop, `activateOutput`, remapping dispatch, mapping-output release and profile colour go through `OutputSink`; `Scripts/Quality/check_sink_boundary.py` (in every check list, `test_sink_boundary.py`) fails on a dispatcher call outside a sink; `StreamBoundaryServiceTests` and `PhysicalOutputExecutorTests+Boundary` cover the sinks and refusals; `check tools` fails when a package executes no tests; snapshots unchanged; all 22 commands pass on `8b9a8fc8`.
- [x] 19.2 Add bounded queue policy per record or default. Verify: slow-consumer test keeps memory bounded and delivers the newest frame. Done: `tuning.frameQueueCapacity` per record, defaulted in every protocol description (64, kept equal to `fallbackQueueCapacity` by `ProtocolDescriptionTests`); newest frame wins, host replies are never evicted and a frame behind a full queue of replies is superseded without closing the device; `slowConsumerKeepsTheQueueBoundedAndDeliversTheNewestFrame` and `frameBehindAQueueOfHostRepliesLeavesTheDeviceOpen`.
- [x] 19.3 Add per-stage timestamps to `ojd diagnose`. Verify: test output lists dispatch and delivery times. Done: read, parse, dispatch, delivery-virtual-device and delivery-endpoint stamps; `DeviceManagerFrameTimingsTests` asserts all five in order and `--plain` adds one timing row per stage.
- [x] 19.4 Add the WebRTC bridge in `Tools/WebRTCBridge/` as its own Swift package on LiveKitWebRTC, an endpoint client (`FeedRequest`/`RumbleCommand` on the game's Mac, `Subscription` on the player's Mac), with out-of-band offer and answer. Verify: a loopback test connects two bridges through a data channel against a test endpoint and passes a frame one way and a rumble command back; the host holds an idle feed open with `KeepAlive`, which the endpoint accepts (feed open past 2 s with keep-alives, E1009 without), with no frame repeated; a socket scan shows no listener; the root `Package.resolved` has no WebRTC package. Done: `Tools/WebRTCBridge` on LiveKitWebRTC; `KeepAlive` in `endpoint.schema.json` and the endpoint (E1011 outside a feed, E1004 with extra members); `VirtualFeedRegistryTests` pins the 2 s default, the feed tests run KeepAlive and E1009 on a short timeout; bridge `HostBridgeTests` show no frame repeat and no write for an invalid peer message; loopback, socket-scan and `test_core_without_webrtc.py` pass.

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

## 24. Follow-ups found during the work

Owns: whatever each item names.
Depends: the item's subject merged.
Verify: the full check list.

- [x] 24.1 Find the cause of each flaky test and fix it: the CLI `E2005: The service did not reply in time` timeouts (`BindingAxisDefaultsTests` and the 17-issue `OpenJoystickDriverCLITests` run), `outputOperationsRemainSerializedWhenAReplacementCancelsTheFirst`, `VirtualFeedRegistryTests.aFailedSendClosesTheFeed`, `EndpointServerTests.theNinthConnectionIsRefused`, and the load failures in `EndpointWebSocketTests`, `RecordCommandTests` and `ConfigCommandTests`. Verify: each suite passes 30 runs in a row while the full `swift test` runs alongside it, and the cause of each is written in its commit. Done: CLI E2005 came from RPC connections queued on a concurrent queue (`BlockingWork.detach` gives each its own thread); the serialized-output test now holds the first call instead of sleeping; the feed-close tests wait for `closeCount`; endpoint test clients set socket options before `connect`; `EndpointServer.status()` leaves closing connections out. Each suite passed 30 runs (CLI 40) beside a full `swift test`; the Record and Config command load failures never reproduced and share the RPC cause.
- [x] 24.2 Build and test `Tools/WebRTCBridge` in CI and in `./Scripts/ojd check tools`. Verify: a CI job and `ojd check tools` run the package's `swift test`. Done: `ojd check tools` runs `swift test` in `Tools/WebRTCBridge` after the SDL probe build, and the CI step runs it.
- [x] 24.3 Add a wiki page for the WebRTC bridge, linked from `wiki/Home.md`. Verify: markdownlint passes and the page's commands match `ojd-webrtc-bridge --help`. Done: `wiki/WebRTC-Bridge.md`, linked from `wiki/Home.md`; its usage block matches the bridge's usage text.
- [x] 24.4 Test the WebRTC bridge against the real endpoint server, not a fake. Verify: a test runs a host bridge against an in-process `EndpointServer`: a granted feed reaches the virtual device and stays open on `KeepAlive`; an ungranted token gets E1002 and no virtual gamepad appears. Done: `EndpointBridgeTests` runs a `HostBridge` from `Tools/BridgeCore` against an in-process `EndpointServer`: a granted feed reaches the virtual device and stays open on `KeepAlive`; a read-only or unknown token gets E1002 and no gamepad.
- [x] 24.5 Show the serving route and persona in `ojd controller show` (text and `--json`, in `cli-output.schema.json`). Verify: CLI tests for each route, and the GUI coverage matrix names the field's GUI place. Done: `controller show` prints `server`, and `--json` carries `ownership.server` and `ownership.serverSource` in `cli-output.schema.json`; CLI tests per route and the GUI coverage matrix entry; all 21 commands pass on `682279d8`.
- [x] 24.6 Include the per-stage timings in `ojd diagnose --bundle`. Verify: a test reads the five stage stamps from the bundle. Done: `data.frameTimings` in the bundle from `ojd diagnose --bundle` and the app's support report, required in `report.schema.json`; `DiagnoseCommandTests.bundleReadsTheFiveStageStampsOfTheNewestFrames`, the app and binding tests, and the Python schema tests.
- [ ] 24.7 Give every rule that Python's schema tests reject a Swift decoder test rejecting the same input. Verify: a repository test lists the Python negative cases for `controller.schema.json` and the protocol descriptions and fails when one has no Swift counterpart.
- [x] 24.8 Pin Biome in `package.json` and run the pinned binary in the hook, the JSON writers and CI. Verify: `biome --version` from each path prints the pinned version, and the `biome.json` `$schema` names the same version. Done: `@biomejs/biome` 2.5.15 exact in `package.json`; `Scripts/Quality/biome_binary.py` resolves the checkout's or the main checkout's `node_modules/.bin/biome`, refuses a version other than the pin and never uses PATH; the hook, `biome_format.py`, the capability check, the check lines and CI use it; `test_biome_pin.py` checks the pin equals the `biome.json` `$schema` version.
- [x] 24.9 Keep one check list: `AGENTS.md`, `Scripts/README.md`, the `justfile` and CI run the same commands (today `ojd errors regenerate --check` is only in the `justfile`, and `ojd check tools` and `ojd snapshots check` are missing from `AGENTS.md`). Verify: a repository test compares the four lists and fails on a difference. Done: `AGENTS.md` holds the canonical list; `Tests/RepositoryScripts/test_check_list.py` compares it with `Scripts/README.md`, the `justfile`, `ci.yml` and the `release.yml` gate steps; all 21 commands pass on `aab00628`.
- [x] 24.10 Make `ojd-webrtc-bridge --help` print its usage to standard output and exit 0; a bad argument still prints usage to standard error and exits non-zero. Verify: bridge tests for both cases, and the wiki page's usage block matches the output. Done: `BridgeCommandLine.swift` with `BridgeProcessTests` for `--help` (stdout, exit 0) and a bad argument (stderr, non-zero); all 21 commands pass on `aab00628`.
- [x] 24.11 Give each long-lived `EndpointServer` connection its own thread, as 24.1 did for the local RPC server, so blocked connections cannot starve new ones under load. Verify: a test opens the connection limit of idle clients and a new client is still served (or refused with its error) within its timeout. Done: each socket and WebSocket connection runs on its own thread via `BlockingWork.detach`, as 24.1 does; the saturation tests fail 10/10 on the old code and pass 10/10 on the fix.
- [x] 24.12 Find and fix the cause of the `ReportSenderTests.nativeSendThatNeverFinishesTimesOutAtTheDeadline` failure under load. Verify: the test passes under `swift test` run in parallel with a CPU load, ten times in a row. Done: feed and transition deadlines run on `DeadlineTimer` with an injectable `VirtualFeedClock`; `eventually` polls every 1 ms; 20 filtered runs under CPU load passed; full 22 passed on b4f78ab8.
- [x] 24.13 Find and fix the cause of the `RemappingRouterReentrancyTests.transactionAdmissionClosesQueuedWindowAfterOuterApply` failure under load. Verify: the test passes under `swift test` run in parallel with a CPU load, ten times in a row. Done: the transition admission window closes on the same `DeadlineTimer`; 20 filtered runs under CPU load passed; full 22 passed on b4f78ab8.
- [x] 24.14 Add an equivalence snapshot of output mapping: the virtual report bytes each persona produces from a fixed set of canonical frames, so a mapping change (such as PlayStation Share/Create moving to the Back bit in 15.1) shows as a snapshot difference. Verify: `ojd snapshots check` covers it, and a planted bit change fails it. Done: `Tests/EquivalenceSnapshots/output-mapping.txt` records each persona's report bytes for every control id, stick and trigger extremes and one combined frame; `snapshots check` covers it, and a planted bit move fails it with 4 differences.
- [x] 24.15 Decide and document every control a virtual persona drops or merges: `TouchpadClick` (unmapped in both), `Capture` (unmapped in `sdl-compatible`), `RightTrackpadClick` sharing `RightStickClick`'s bit, kept only for a controller without a right stick click so Steam Deck and Triton pad clicks stop landing on R3 (the stick Y sign is 15.4), and the list of controls each persona carries on the wiki. Verify: `output-mapping.txt` and `sdl-mappings.txt` match the decision, and tests cover each changed mapping. Done: `TouchpadClick` is uncarried in both personas (the generic layout's 16 buttons are the `1209:4A4F` contract; sdl-compatible has no slot) and `Capture` in sdl-compatible (the Xbox packet has no Share field), each listed with its reason in `buttonBit(for:)`. `RightTrackpadClick` goes to R3 only when the record's effective controls (description controls with `capabilityDelta`) have a right pad click and no right stick click, so Steam Deck and Triton pad clicks stay unmapped. The rule is shared by delivery and `Passthrough`, which reads it once per update. `PersonaControlMappingTests` covers it. The wiki table "What the virtual controller carries" is linked from `Bindings-and-Actions.md`, and the snapshots record the change. `swift test` ran with `PhysicalOutputExecutorTests` skipped (24.17).
- [ ] 24.16 Carry out the design's Migration Plan (decision 13, none): every stored kind (profiles, records, patches, persona files, access grants, user defaults) refuses a file that lacks the supported `apiVersion` or fails the current schema through its ordinary invalid-file path, with no detection of earlier shapes. The CHANGELOG gives no conversion steps. Verify: a test per stored kind loads a file without the supported `apiVersion` and gets the unsupported-version error; `rg` finds no shape-specific detection.
- [ ] 24.17 Find and fix why `PhysicalOutputExecutorTests` stalls under load: `failedStopRumbleLeavesNoClaimAndRetryWrites` hung twice and the Kit test process ended silently during `concurrentStatefulCommandsWriteInEncodeOrder`. Fix the cause in the product path when it is there, and fix siblings with the same pattern. Verify: a loop of the suite under CPU load that stalled before passes every run, and a regression test turns a hang into a failure with a time limit.
- [ ] 24.18 After H6, write the DS3 Bluetooth pairing walkthrough in the wiki from the verified steps: the 0xF4 enable report, the host address write, and what the user sees. Verify: each step names the hardware check (H6) that confirmed it; nothing states which DS3 unit is genuine.
- [ ] 24.19 Remove every table and detector of earlier words in Swift and Python: `RenamedWord`, `RenamedFlags`, error E5006 and its strings in the template and every locale, `cli.error.renamed_flag`, the `.documentField(in:)` rows, the decoders and stores that recognize old words or old `AccessGrants.json` shapes, the old-name map in `ControlVocabularyTests`, and the tests that list old words (`ExtensionWordsTests`, `AccessWordsTests`, `test_renamed_words.py`, `test_extension_words_schema.py`, `test_access_words_schema.py`, and the "old field rejected" cases). Earlier input fails through the same path, code and message as any unknown or invalid input. Regenerate `ErrorCodes.json` outputs and `wiki/Error-Codes.md`. Verify: `rg` for each removed name and old word over Sources, Tests, Tools, Scripts and Resources finds only current ids; a test shows an earlier word and a random unknown word give identical errors.
- [ ] 24.20 Audit the repository for any other backward compatibility: aliases, typealiases, `@available(..., deprecated|renamed:)`, deprecated forwarding, compatibility flags or settings, fallback decoders, upcasters, dual readers or writers, legacy code paths, migration code and migration guides, in Swift, Python, schemas, scripts, localized strings and docs. Remove each, or keep it only when it is a current feature whose name merely contains such a word (for example the original Steam Controller), and record that reason in the task note. Verify: the task note lists every hit with its decision; the audit `rg` patterns return only the recorded keeps.
- [ ] 24.21 Rewrite comments, doc comments, help and error strings, schema `description` fields, `wiki/` and `docs/` so they describe current behavior only, per `AGENTS.md` "Comments and documentation": no history ("renamed", "formerly", "previously", "no longer", "replaces", "since 0.x"), no task, review or release references, no meta-commentary. Fix `wiki/Controller-Records.md` "Schema Versions and Compatibility" ("how to update a file") and remove conversion steps and hint descriptions from `CHANGELOG.md`. Split by area: Kit sources, other Sources and Tools, Tests and Scripts, docs and wiki. Verify: the `rg` patterns from the task note return only reviewed current-behavior uses, each listed.
- [ ] 24.22 Make `StartupLifetimeTests` deterministic under full-suite load: `HIDAccessFailureTearsDownPhysicalStateAndWaitsForPermissionWatchRetry` (`attemptCount() == 2`) and `staleAccessFailureTeardownCannotRemoveConnectionFromNewDetectionSession` each failed once in a full run and pass in isolation. Find the wait that depends on timing, fix it in the product path when it is there, and fix siblings with the same pattern. Verify: a loop of the suite under CPU load passes every run, and the full `swift test` passes.

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
- [ ] H10 Stutter: measure with the 19.3 timestamps, with and without the WebRTC bridge.
- [ ] H11 Native speakers review the 20 non-English locales' new strings from 12.4 and 15.x.

## Workflow follow-up

- Push, tag, notarize and publish are the maintainer's actions and need confirmation.
- Turn on GitHub Pages so the schema `$id` URLs resolve (open item 8).
- Archive this change after `release-0-6-0-alpha-1` is archived, then convert `pending-deltas.md` into MODIFIED and REMOVED deltas.
