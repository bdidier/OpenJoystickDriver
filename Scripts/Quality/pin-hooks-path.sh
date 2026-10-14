#!/usr/bin/env bash
# husky sets core.hooksPath to the relative .husky/_, which Git resolves in each worktree.
# A worktree without its own install then skips every hook silently, so point the shared
# setting at the main checkout's hooks instead.
set -euo pipefail

[ "${HUSKY-}" = "0" ] && exit 0

common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
hooks_path="$(dirname "$common_dir")/.husky/_"
if [ ! -d "$hooks_path" ]; then
  echo "error: $hooks_path does not exist; run \`bun install\` in the main checkout first" >&2
  exit 1
fi
git config core.hooksPath "$hooks_path"
