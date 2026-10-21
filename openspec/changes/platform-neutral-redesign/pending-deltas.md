# Pending deltas against the eight capabilities of `release-0-6-0-alpha-1`

`openspec/specs/` is empty until `release-0-6-0-alpha-1` is archived, so this file holds the deltas as text.
After the archive, copy each block into `specs/<capability>/spec.md` of this change as `## MODIFIED Requirements` or `## REMOVED Requirements`, with the requirement header matching the archived text exactly, then run `openspec validate platform-neutral-redesign --strict`.
Requirement names below are those of the old change (`REQ-n ...`).

## driverkit-signing

- REQ-26 A host profile that grants more user-client IDs is accepted: unchanged.

## mod-localization

- REQ-11 E3029 explained in the user's language: MODIFIED. The key `error.E3029` becomes `error.E3029.message` under the new namespace, and the text must come from the catalog in app, CLI and endpoint.
- REQ-12 Reviewed mod strings: MODIFIED. Keys `cli.explain.area.mod` and `cli.mod.*` become `cli.explain.area.mod` and `cli.mod.<command>.*` as the re-key maps them; every key has a translator comment and positional specifiers; the checker is the updated `check_localization_keys.py`.

## mod-packages

- REQ-1 to REQ-5, REQ-17: MODIFIED. Package contents are `controllers`, `patches`, `virtualDevices`, `profiles` (renamed from `records` and `personas`); every package file carries `apiVersion` and `kind`; "persona" becomes "virtual device".
- REQ-6 to REQ-9 (`ojd mod validate|install|list|remove`): MODIFIED. Help, output and error wording follow `cli-surface`; flags `--dry-run`, `--force`, `--json` stay.
- REQ-10 Mod output envelopes: MODIFIED. Text becomes: "Each `ojd mod` command MUST print the `apiVersion`/`kind` envelope with `apiVersion: openjoystickdriver/v1alpha1`, and `Resources/Schemas/cli-output.schema.json` MUST have one `$defs` entry per `ojd mod` command path." The path `Resources/Schemas/v1beta1/` is removed.
- Manifest `requires` handling (REQ-17): unchanged in behavior; the `ModPackage` kind carries the header.

## mod-sdk

- REQ-13 Sample package: MODIFIED. The sample's identity ids use a documented sample ID that is not `1209:0001`; the sample validates against the `v1alpha1` schemas and `check schemas` covers `docs/sdk/sample/**`.
- REQ-14 Mod documentation: MODIFIED. Adds that records can now describe modes, probes and layouts, so a clone or new controller needs no source change; the first statement about the Apple-signed USB extension list stays.

## release-readiness

- REQ-15 Release CHANGELOG section: MODIFIED. The section lists every **BREAKING** item of this change, the rejected document shapes, the new default persona, and the removed CLI words.
- REQ-16 Full check list: MODIFIED. Same list, plus `crowdin.yml` parse check and the schema constant-equality test; all run on the final tree.

## usb-device-detection

- REQ-24 Original Xbox One controller is listed: MODIFIED. The route is `ExtensionOwned` from the record, and the extension match list that lists `045E:02D1` is generated from records. Behavior is unchanged.

## virtual-input-delivery

- REQ-23 Virtual stick reports are not delayed or held: MODIFIED. The queue policy is the per-record or default value declared in tuning; the requirement applies to every persona, and the check includes the `Generic` persona.

## virtual-ownership

- REQ-18 Ownership toggle on the command line: MODIFIED. New text: "`ojd controller claim CONTROLLER [--dry-run] [--json]` and `ojd controller release CONTROLLER [--dry-run] [--json]` MUST set who serves a controller model that the system supports natively: `release` leaves it to the system, `claim` makes OJD seize it and publish its own virtual gamepad, with the same effect as a record `server` of `system` or `ojd`." Scenarios use the new words.
- REQ-19 Ownership toggle in the app: MODIFIED. Words become "Served by: System / OpenJoystickDriver"; the control is in the Controllers area detail.
- REQ-20 Virtual ownership publishes a virtual gamepad: MODIFIED. The gamepad uses the chosen persona, `Generic` by default.
- REQ-21 Ownership persists and applies without replugging: MODIFIED. The route is re-evaluated by the single serving policy; a suspended controller stays suspended.
- REQ-22 Raw-USB families refuse the toggle: MODIFIED. The refusal is computed from the record's route (`ExtensionOwned` or raw access), not from a family list in code.
