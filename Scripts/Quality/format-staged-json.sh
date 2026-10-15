#!/usr/bin/env bash
# Formats the staged JSON files with Biome and stages the result.
# A file whose working copy matches what was staged gets the formatted text too;
# a partly staged file keeps its unstaged edits.
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
staged_copy="$(mktemp -d "${TMPDIR:-/tmp}/ojd-staged-json.XXXXXX")"
trap 'rm -rf "$staged_copy"' EXIT INT TERM

paths=()
while IFS= read -r -d '' path; do
  paths+=("$path")
done < <(git diff --cached --name-only -z --diff-filter=ACMR -- '*.json' '*.jsonc')
if ((${#paths[@]} == 0)); then
  exit 0
fi

printf '%s\0' "${paths[@]}" | git checkout-index -z --stdin --prefix="$staged_copy/"
biome format --write --config-path="$repository_root/biome.json" --vcs-enabled=false \
  "$staged_copy" >/dev/null

for path in "${paths[@]}"; do
  staged="$(git rev-parse ":$path")"
  formatted="$(git hash-object -w -- "$staged_copy/$path")"
  if [[ "$formatted" == "$staged" ]]; then
    continue
  fi
  mode="$(git ls-files --stage -- "$path" | cut -d ' ' -f 1)"
  git update-index --cacheinfo "$mode,$formatted,$path"
  if [[ -f "$repository_root/$path" &&
    "$(git hash-object -- "$repository_root/$path")" == "$staged" ]]; then
    cp "$staged_copy/$path" "$repository_root/$path"
  fi
  printf 'Formatted %s with Biome.\n' "$path"
done
