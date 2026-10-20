# AGENTS.md

- Read `CONTRIBUTING.md` (incl. `#ai-agents`), `LOCALIZATION.md`, `wiki/Home.md`, `Resources/Schemas/AGENTS.md`.
- Follow the active OpenSpec change in `openspec/changes/`. Ground claims in source, tests, schemas or hardware evidence.
- No compatibility: no aliases, shims, fallback decoders, dual readers/writers or migrations. Earlier names and shapes fail like any invalid input; replace them everywhere in one change.
- No hidden behavior: no silent fallback, default or retry over invalid input or failures. Real behavior gets a name, a test and user-facing text.
- Remove code only after finding every reference.
- Comments and docs state current behavior and its reason. No history words ("renamed", "was", "now", "new", "old", "legacy"), no task/review/agent/issue references. History goes only in `CHANGELOG.md`.
- Never hand-edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`: run `./Scripts/ojd catalog regenerate --write` / `./Scripts/ojd driverkit generate`.
- After changing `Resources/ErrorCodes.json`, run `./Scripts/ojd errors regenerate --write`.
- No SVGs, no secrets. Confirm destructive writes and publication first.
- Fix code/spec gaps and Swift/Python divergences now; add larger fixes as tasks in the active change.
- Checks: write all code for a task, build once, test the changed area, run `just check` once; rerun only failures. No polling loops. `just check-fast` skips Swift. `./Scripts/ojd repair swiftpm-module-cache` only for module-cache mismatches.
