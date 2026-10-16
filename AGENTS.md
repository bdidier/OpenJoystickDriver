# AGENTS.md

## Before Editing

- Read `CONTRIBUTING.md`, `LOCALIZATION.md`, `wiki/Home.md`, and `Resources/Schemas/AGENTS.md`.
- Follow the active OpenSpec change in `openspec/changes/`.
- Ground every claim in source, tests, schemas, or recorded hardware evidence.

## No Compatibility

- No aliases, shims, compatibility flags, fallback decoders, dual readers or writers, or migrations.
- No list, hint, or test of earlier names, fields, keys, codes, or file shapes. Earlier input fails like any invalid input.
- Replace an earlier form everywhere in one change: code, tests, fixtures, schemas, snapshots, strings, and docs.

## No Hidden Behavior

- No silent fallback, default, or retry that covers for invalid input or a failed operation.
- Give real behavior a name, a test, and user-facing text where its effect is visible.
- Remove code only after finding every reference; move a real use to its owner.

## Comments & Docs

- State current behavior and its reason only, in code, help, errors, schemas, `wiki/`, and `docs/`.
- No history words ("renamed", "formerly", "was", "no longer", "now", "new", "old", "legacy", "replaces").
- No references to tasks, reviews, agents, issues, or releases, and no narrated reasoning.
- History goes only in `CHANGELOG.md`, with no conversion steps.

## Boundaries

- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`; regenerate them with `./Scripts/ojd catalog regenerate --write` and `./Scripts/ojd driverkit generate`.
- Run `./Scripts/ojd errors regenerate --write` after changing `Resources/ErrorCodes.json`.
- Do not add SVGs or secrets.
- Confirm destructive writes and publication first. Follow `CONTRIBUTING.md#ai-agents`.

## Architecture

- Settle the long-term design early.
- Fix any gap between code and spec, or between two implementations of one rule, in Swift and Python alike. Do not defer it.
- Add a fix larger than the task to the active OpenSpec change as a task, and do it.

## Checks

- Write all the code for a task first. Then build once, run the tests of the changed area, and run `just check` once. Rerun only what failed.
- Do not build or test after each small edit, and leave no monitor or polling loop running.
- `just check-fast` skips the Swift build and tests. Use `./Scripts/ojd repair swiftpm-module-cache` only for a module-cache mismatch.
