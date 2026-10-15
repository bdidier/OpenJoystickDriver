# AGENTS.md

OpenJoystickDriver is a userspace gamepad driver with a platform-neutral core. macOS is the first host. Ground every claim in source, tests, schemas, or recorded hardware evidence.

Before editing, read `CONTRIBUTING.md`, `wiki/Home.md`, `LOCALIZATION.md`, and `Resources/Schemas/AGENTS.md`. The active OpenSpec change under `openspec/changes/` is the plan of record.

## Current design only

The tree contains one design: the current one. Git history and release tags keep earlier designs.

- Do not keep backward compatibility in any form. That includes aliases, typealiases, deprecated forwarding, compatibility flags or settings, fallback decoders, upcasters, dual readers or writers, shims, upgraders, migrations, and migration guides.
- Do not keep knowledge of earlier names, words, flags, fields, keys, codes, or file shapes. Code, tests, schemas, and localized strings do not list them, detect them, or suggest a replacement for them. Earlier input fails like any other unknown or invalid input, with the same path, error code, and message.
- Do not add hidden behavior. Do not add a silent fallback, default, or retry that covers for invalid input or a failed operation. If the behavior is real, make it visible: give it a name, a test, and user-facing text where a user can see its effect.
- A change replaces the earlier code completely. In the same change, update every producer, consumer, test, fixture, schema, snapshot, localized string, and document. Do not leave the earlier form beside the new one.

## Comments and documentation

- Comments and doc comments say what the code does now and why. They do not say what it did before or how it changed. Do not write "renamed", "formerly", "previously", "was", "no longer", "now", "new", "old", "legacy", "replaces", or "since 0.x" about the code itself.
- Comments do not refer to tasks, reviews, agents, issues, release numbers, or the work that produced them. Do not narrate reasoning or review discussion.
- The same rules apply to help text, error text, schema `description` fields, `wiki/`, and `docs/`.
- `CHANGELOG.md` is the one place for history. It records what each release changes. It does not tell users how to convert earlier files, commands, or settings.

## Boundaries

- Do not edit generated records in `Sources/OpenJoystickDriverKit/Resources/Controllers/` or generated DriverKit files in `.build/driverkit/generated/`.
- Regenerate the catalog with `./Scripts/ojd catalog regenerate --write` only after you change its authored inputs on purpose.
- Generate DriverKit files with `./Scripts/ojd driverkit generate`.
- Regenerate the error catalog outputs with `./Scripts/ojd errors regenerate --write` after you change `Resources/ErrorCodes.json`.
- Do not add SVGs or secrets.
- Confirm destructive writes and publication before you run them.
- Issues, comments, and pull requests follow `CONTRIBUTING.md#ai-agents`.

## Architecture

- Settle the long-term design early. When work shows a gap between the code and the spec, or two implementations of one rule that disagree, fix it toward the spec in Swift and Python alike. Do not carry the gap forward or defer it.
- If the fix is larger than the task, add it as a task to the active OpenSpec change and do it. Do not leave it as a note.
- Before you call a value or a code path unused, find every reference to it. Remove it only when it has no use. A real use moves to its current owner.

## Checks

Run the applicable commands from the repository root:

```bash
./Scripts/ojd catalog regenerate --check
./Scripts/ojd errors regenerate --check
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

Use `./Scripts/ojd repair swiftpm-module-cache` only to repair a SwiftPM module-cache mismatch.
