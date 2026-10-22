# AGENTS.md

- Read `CONTRIBUTING.md` (incl. `#ai-agents`), `LOCALIZATION.md`, `wiki/Home.md`, `Resources/Schemas/AGENTS.md`.
- Follow the active OpenSpec change in `openspec/changes/`. Ground claims in source, tests, schemas or hardware evidence.
- No compatibility until `v1.0.0` stable: no aliases, shims, fallback decoders, dual readers/writers or migrations. Earlier names and shapes fail like any invalid input; replace them everywhere in one change.
- No hidden behavior: no silent fallback, default or retry over invalid input or failures. Real behavior gets a name, a test and user-facing text.
- Remove code only after finding every reference.
- Comments and docs state current behavior and its reason. No history words ("renamed", "was", "now", "new", "old", "legacy"), no task/review/agent/issue references. History goes only in `CHANGELOG.md`.
- Never hand-edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`: run `./Scripts/ojd catalog regenerate --write` / `./Scripts/ojd driverkit generate`.
- Review every translation you add or change against `LOCALIZATION.md` (Meaning, Punctuation) before committing, and fix what fails; passing `LocalizationTests` is not a review.
- After changing `Resources/ErrorCodes.json`, run `./Scripts/ojd errors regenerate --write`.
- A controller record or protocol description that Swift rejects gets a case (`name`, `code`, `document`, `fileName` for descriptions) in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/`; add `"schema": true` only when the JSON Schema alone rejects it.
- No SVGs, no secrets. Confirm destructive writes and publication first.
- Swift is canonical. Python tooling calls Swift or reads what Swift generates; it does not re-implement Swift logic. Fix code/spec gaps and any Python copy of Swift logic now; add larger fixes as tasks in the active change.
- Checks: write all code for a task, build once, test the changed area, run `just check` once; rerun only failures. No polling loops. `just check-fast` lints Swift but skips the Swift build and tests.
