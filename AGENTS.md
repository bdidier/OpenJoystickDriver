# AGENTS.md

OpenJoystickDriver is a macOS userspace gamepad driver. Ground claims in source, tests, schemas, or recorded hardware evidence.

Before editing, read `CONTRIBUTING.md`, `wiki/Home.md`, `LOCALIZATION.md`, and `Resources/Schemas/AGENTS.md`.

## Boundaries

- Do not edit generated records in `Sources/OpenJoystickDriverKit/Resources/Controllers/` or generated DriverKit files in `.build/driverkit/generated/`.
- Regenerate the catalog with `./Scripts/ojd catalog regenerate --write` only after intentionally changing its authored inputs.
- Generate DriverKit files with `./Scripts/ojd driverkit generate`.
- Do not add SVGs or secrets.
- Confirm destructive writes and publication before running them.
- Issues, comments, and pull requests follow `CONTRIBUTING.md#ai-agents`.

## Architecture

- Settle on the long-term design early. When work exposes a gap between the code and the spec, or two implementations of one rule that disagree, fix it toward the spec in Swift and Python alike, instead of carrying the gap forward or deferring it.
- If the fix is larger than the task at hand, add it as a task to the active OpenSpec change and do it; do not leave it as a note.

## Checks

Run applicable commands from the repository root:

```bash
./Scripts/ojd catalog regenerate --check
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
python3 Scripts/Quality/check_localization_keys.py
./Scripts/ojd check driverkit
swift test
```

For parser or protocol changes, also run `./Scripts/ojd test parsers-macos14`. Use `./Scripts/ojd repair swiftpm-module-cache` only to repair a SwiftPM module-cache mismatch.
