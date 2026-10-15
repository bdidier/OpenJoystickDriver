# AGENTS.md

`Resources/Schemas/` is the sole owner of OpenJoystickDriver's machine-readable document contracts.

- Use JSON Schema Draft 2020-12.
- Reuse the controller, controller-patch, virtual-device, mod-package, protocol-description, settings, report, cli-output, profile, or error-codes schema family. `cli-output.schema.json` has one `$defs` entry per `ojd` command, named by its command path in lowerCamelCase.
- `vocabulary.schema.json` is the one definition of the control ids (`$defs/control`, UpperCamelCase) and the subsets other schemas `$ref`. It has only `$defs` and no `kind`, because no document is an instance of it. Controller records, profiles, `ojd` JSON and the endpoint `Frame` name controls by these ids and by no other spelling; the Swift enum `Control` mirrors them and a test keeps both equal.
- Do not add schemas scoped to one controller, consumer, diagnostic command, experiment, date, issue, pull request, or agent task.
- Keep shared parser behavior out of controller records. Schemas describe only fields emitted or consumed by an existing repository-owned interface.
- Controller records contain operational facts only. Do not add provenance, verification, confidence, evidence-level, source-note, or review-state fields or flags such as `experimental` and `needsHardwareTest`. Keep source revisions in `ControllerSources.lock.json` and accepted test observations in human-readable testing documents, issues, and Git history.
- Support reports contain observed diagnostic state only. Do not embed test plans, verification claims, inferred evidence levels, or compatibility migration payloads.
- Keep every schema strict. Prefer typed fields, enums, discriminated variants, local `$ref` values, and `additionalProperties: false`. Add length, count, or range limits only when the producer enforces the same limit.
- Schemas are flat files, `Resources/Schemas/<kind>.schema.json`. Do not add a version directory or a second live version of a schema.
- Every document kind carries `apiVersion: openjoystickdriver/v1alpha1` and an UpperCamelCase `kind`, both required and fixed by `const`. A reader rejects a missing or unknown `apiVersion` and a `kind` it does not read, and names the file, the version found, and the supported one. Instances do not declare `$schema`.
- Each schema's `$id` is `https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha1/<kind>.schema.json`. The version constant, the `$id` base, and the kind of each schema have one source for tooling, `Scripts/Catalog/schema_header.py`, and one for Swift, `OpenJoystickDriverAPI.version`; a test keeps them and every schema's `apiVersion` const equal. The IDs are names: nothing publishes them yet, and nothing fetches them.
- Change the one live schema for an artifact class atomically with every producer, consumer, authored input, generated output, and validation rule.
- Raise the version, in every schema and both constants, only for the release that promotes or breaks the contract; do not keep two live versions or dated successor files. Do not retain dual writers, aliases, fallback decoders, upcasters, or compatibility shims. A crosswalk to SDL, evdev, HID, Apple and W3C names is documentation, not a schema alias: `Resources/Vocabulary/crosswalk.json` has one row per control id, no schema accepts or maps any name in it, and no reader decodes an old or foreign name to an id. Tests round-trip it; it is the one source for those names.
- Follow the compatibility policy in `wiki/Controller-Records.md`.
- Do not duplicate schema field definitions or enums in handwritten validators. Code may enforce cross-document and runtime invariants only.
- Never fetch schemas at runtime. Repository validation must resolve them locally.

Validate schema changes with the repository schema/profile checks, focused producer tests, catalog regeneration checks, and `git diff --check`. Git history and releases preserve old contracts; the worktree contains only the current one. The schema gate must cover every file in both controller-record trees, not just sample controllers or schema documents.
