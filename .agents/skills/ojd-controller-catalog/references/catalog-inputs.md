# Catalog Inputs

## Contents

- [Authored inputs](#authored-inputs)
- [Controller add](#controller-add)
- [Controller patch](#controller-patch)
- [Lockfile revision](#lockfile-revision)
- [Protocol driver](#protocol-driver)
- [Evidence classes](#evidence-classes)

## Authored Inputs

**Definition.** The generator combines four authored inputs into the generated records under `Sources/OpenJoystickDriverKit/Resources/Controllers/`:

```text
ControllerSources.lock.json                           ─┐
Resources/Controllers/<vid>/<vid>-<pid>.json          ─┤
Resources/ControllerPatches/<vid>/<vid>-<pid>.patch.json ─┼─> ./Scripts/ojd catalog regenerate --write
Resources/Schemas/*.schema.json                       ─┘      ─> generated records
Sources/OpenJoystickDriverKit/Protocol/  (parsing and transport behavior, Swift)
```

- `ControllerSources.lock.json` (repository root) pins `linux` and `sdl` upstream commits with a SHA-256 per file.
- `Resources/Controllers/` holds one `Controller` file per device that no pinned source knows, validated by `Resources/Schemas/controller.schema.json`. `Resources/ControllerPatches/` holds one `ControllerPatch` file per device (`selector.vendorID` and `selector.productID`, plus a `patch` body), validated by `Resources/Schemas/controller-patch.schema.json`.
- `Resources/Schemas/` owns the document shapes. Its `AGENTS.md` sets the rules: strict schemas, one live schema per artifact class, no versioned successor files.

**Use when.** Every catalog change starts at one of these inputs.

**Do not use when.** A behavior applies to a whole protocol family. That is Swift in `Protocol/`, not per-device data.

**Verify.** After `--write`, `./Scripts/ojd catalog regenerate --check` exits 0, and `git status --short Sources/OpenJoystickDriverKit/Resources/Controllers` lists only the intended records.

## Controller Add

**Definition.** A complete record for a VID/PID that no pinned upstream source knows. The file is a plain `Controller` document at `Resources/Controllers/<vid>/<vid>-<pid>.json` (lowercase hex path).

**Use when.** `rg` finds the VID/PID in neither the generated records nor the pinned upstream files.

**Do not use when.** A Linux-derived record already has the VID/PID. The generator (`load_authored` in `Scripts/Catalog/generate_controller_catalog.py`) raises an add-versus-upstream conflict; write a patch instead. SDL-only identities merge after the authored files, and an add wins over an SDL row.

**Example.** Copy the shape from an existing add, such as `Resources/Controllers/37d7/37d7-2801.json`, then replace every value with values observed for the new device.

**Verify.** `./Scripts/ojd check profiles` and `./Scripts/ojd check schemas` exit 0, and the generated diff adds exactly one record.

## Controller Patch

**Definition.** A `ControllerPatch`: an RFC 7396 merge patch of the upstream record for one device.

**Example** (`Resources/ControllerPatches/045e/045e-02d1.patch.json`):

```json
{
  "apiVersion": "openjoystickdriver/v1alpha1",
  "kind": "ControllerPatch",
  "selector": { "vendorID": 1118, "productID": 721 },
  "patch": {
    "usb": {
      "endpoints": { "in": 129, "out": 1 },
      "configuration": "set1-before-claim"
    }
  }
}
```

**Use when.** An upstream record exists but one section, such as the endpoints, USB configuration, or quirks, is wrong for macOS user-space access.

**Do not use when.** The whole record is wrong. In that case either the upstream revision needs a bump, or the device is not the one upstream describes; check before patching.

The merge is RFC 7396 and recursive: an object merges key by key, a value replaces, an array replaces whole, and `null` deletes the key. A patch that changes `protocol.family` must `null` the upstream `protocol` keys that the new family does not read, and emptying a section needs `null` on the whole section, not on its last key. The generator also rejects an orphan patch (no upstream record) and a redundant patch (one that changes nothing). The Swift loader merges with the same rules, so the generated record and the runtime record agree.

**Cost removed.** A full-record copy stops tracking upstream fixes. A patch keeps every key that it does not set.

**Verify.** The generated diff for the device changes only the patched keys, and no key disappeared unintentionally.

## Lockfile Revision

**Definition.** Moving `ControllerSources.lock.json` to a newer upstream commit and updating its per-file `sha256`. `./Scripts/ojd catalog xpad [options]` generates review-only records from a pinned `xpad.c`; see `docs/development/xpad-import.md`.

**Use when.** Upstream added or fixed the device, and the review accepts every other record change that the new revision brings.

**Do not use when.** Only one device is needed and the bump churns unrelated records the change cannot review. Use a patch and note the upstream commit in the testing page.

**Verify.** Review the whole generated diff. A lockfile bump can change many records, so every change needs a reason.

## Protocol Driver

**Definition.** Swift parsing, handshake, and output encoding under `Sources/OpenJoystickDriverKit/Protocol/Drivers/{Generic,Nintendo,Sony,Valve,Vendor,Xbox}/`, conforming to `PhysicalProtocolDriver` (`Protocol/Drivers/PhysicalProtocolDriver.swift`).

**Use when.** The device speaks a report layout or handshake that no existing driver implements.

**Do not use when.** An existing driver handles the layout and only identity data differs. Use a patch.

**Verify.** Add a packet-fixture test under the mirrored `Tests/OpenJoystickDriverKitTests/Protocol/` directory and run it with `swift test --filter`, then `./Scripts/ojd test parsers-macos14`. Follow the `ojd-swift-change` rules for file placement and naming.

## Evidence Classes

| Class | Establishes | Does not establish |
| --- | --- | --- |
| Source-backed | Upstream identity and classification | That macOS opens the device, or any hardware behavior |
| Packet/parser-backed | Behavior for the supplied reports | Physical descriptors, handshake, reconnect |
| Record-probe-backed | The candidate record opens and decodes in `./Scripts/ojd diagnose record` | Every control, actuator, or consumer |
| Hardware-verified | One recorded physical result for one claim | Other macOS versions, modes, or models |

Source revisions stay in the lockfile. Evidence status goes in `docs/testing/` pages, issues, and Git history, never in records.
