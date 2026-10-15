# Repository Scripts

`./Scripts/ojd` is the supported entrypoint for repository-specific behavior. Just orchestrates standard formatters, linters, type checkers, tests, and those repository routes.

The dispatcher owns command parsing; `Scripts/Command/` owns process execution, while `Scripts/Platform/` owns capability models, resolution, and route requirements. The remaining feature groups own narrow implementations.

Use `./Scripts/ojd --help` for supported routes and `./Scripts/ojd --version` for the project version. This dispatcher is not the product `ojd`; the shipped CLI is the app binary, run as `ojd`. Run the standard tools directly or use the equivalent `just lint`, `just check-fast`, and `just check` recipes:

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

`snapshots check` runs the equivalence snapshot tests and prints the changed, added, and removed records against the files in `Tests/EquivalenceSnapshots/` (parsed frames, catalog index, record routes, DriverKit match list, SDL mappings, and the virtual report bytes each persona produces from canonical frames, with a control that has no bit in a persona recorded as `unmapped`); it exits non-zero on any difference. `snapshots write` rewrites those files from the current tree, so run it after any intended behavior change and review the resulting diff.

`catalog regenerate --write` writes generated controller records. DriverKit project generation writes DriverKit output. All other commands retain their documented route-specific effects and requirements.
