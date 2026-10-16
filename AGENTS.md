# AGENTS.md

## Before Editing

- Read `CONTRIBUTING.md`, `LOCALIZATION.md`, `wiki/Home.md`, and `Resources/Schemas/AGENTS.md`.
- Follow the active OpenSpec change in `openspec/changes/`.
- Ground every claim in source, tests, schemas, or recorded hardware evidence.

## No Compatibility

- No aliases, typealiases, deprecated forwarding, or compatibility flags.
- No fallback decoders, upcasters, dual readers or writers, shims, upgraders, or migrations.
- No migration guides or conversion steps.
- No list, detector, hint, or test of earlier names, words, flags, fields, keys, codes, or file shapes.
- Earlier input fails like any unknown or invalid input: same path, error code, and message.
- Replace the earlier form completely in one change: producers, consumers, tests, fixtures, schemas, snapshots, localized strings, and docs.

## No Hidden Behavior

- No silent fallback, default, or retry that covers for invalid input or a failed operation.
- Give real behavior a name, a test, and user-facing text where its effect is visible.
- Find every reference before calling code unused. Remove it only when unused; move a real use to its current owner.

## Comments & Docs

- State current behavior and its reason only.
- No history: "renamed", "formerly", "previously", "was", "no longer", "now", "new", "old", "legacy", "replaces", "since 0.x".
- No references to tasks, reviews, agents, issues, or releases.
- No narrated reasoning or meta-commentary.
- Apply the same rules to help text, error text, schema `description` fields, `wiki/`, and `docs/`.
- History goes only in `CHANGELOG.md`, with no conversion steps.

## Boundaries

- Do not edit generated records in `Sources/OpenJoystickDriverKit/Resources/Controllers/`.
- Do not edit generated DriverKit files in `.build/driverkit/generated/`.
- Run `./Scripts/ojd catalog regenerate --write` only after changing its authored inputs on purpose.
- Run `./Scripts/ojd errors regenerate --write` after changing `Resources/ErrorCodes.json`.
- Generate DriverKit files with `./Scripts/ojd driverkit generate`.
- Do not add SVGs or secrets.
- Confirm destructive writes and publication before running them.
- Follow `CONTRIBUTING.md#ai-agents` for issues, comments, and pull requests.

## Architecture

- Settle the long-term design early.
- Fix any gap between code and spec, or between two implementations of one rule, toward the spec in Swift and Python alike. Do not defer it.
- Add a fix larger than the task to the active OpenSpec change as a task, and do it.

## Checks

- Run the applicable commands from the repository root.
- Write all the code for a task first. Then build once, run the tests of the changed area, and run the full checks once. Rerun only what failed.
- Do not build or test after each small edit.
- Do not leave monitors or polling loops running; wait for the background command to finish.
- Use `./Scripts/ojd repair swiftpm-module-cache` only to repair a SwiftPM module-cache mismatch.

```bash
./Scripts/ojd catalog regenerate --check
./Scripts/ojd errors regenerate --check
./Scripts/ojd vocabulary regenerate --check
./Scripts/ojd check profiles
./Scripts/ojd check schemas
./Scripts/ojd check tools
ruff format --check Scripts Tests/RepositoryScripts
ruff check Scripts Tests/RepositoryScripts
pyright
.build/schema-validator/bin/python -m unittest discover -s Tests/RepositoryScripts
find Scripts -type f \( -name '*.sh' -o -name ojd \) -print0 | xargs -0 shellcheck \
  --external-sources --source-path=SCRIPTDIR
git ls-files -z -co --exclude-standard -- '*.md' ':!.agents/' | xargs -0 markdownlint-cli2
git ls-files -z -co --exclude-standard -- '*.json' '*.jsonc' | xargs -0 node_modules/.bin/biome ci
swift-format lint --recursive --strict Package.swift Sources Tests Tools
swiftlint lint --no-cache --strict
python3 Scripts/Quality/check_swift_file_length.py
python3 Scripts/Quality/check_neutral_core_imports.py
python3 Scripts/Quality/check_sink_boundary.py
python3 Scripts/Quality/check_localization_keys.py
./Scripts/ojd check driverkit
./Scripts/ojd test parsers-macos14
./Scripts/ojd snapshots check
swift test --no-parallel
```
