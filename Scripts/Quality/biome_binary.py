"""Find the pinned Biome binary for one checkout.

The binary is `node_modules/.bin/biome` of the checkout's top level, else of the main
worktree (a linked worktree has no `bun install` of its own). Its version must equal the
`@biomejs/biome` pin in the checkout's `package.json`. A Biome on `PATH` is never used.
Run as a script, it prints the binary path for the top level given as the argument.
"""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys

BINARY = pathlib.Path("node_modules/.bin/biome")


class BiomeBinaryError(OSError):
    """No usable pinned Biome binary exists."""


def pinned_version(toplevel: pathlib.Path) -> str:
    package = json.loads((toplevel / "package.json").read_text(encoding="utf-8"))
    return str(package["devDependencies"]["@biomejs/biome"])


def main_checkout(toplevel: pathlib.Path) -> pathlib.Path:
    """The main worktree: the parent of the repository's common git directory."""
    result = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True,
        check=False,
        cwd=toplevel,
        text=True,
    )
    if result.returncode:
        return toplevel
    return pathlib.Path(result.stdout.strip()).parent


def installed_version(binary: pathlib.Path) -> str:
    result = subprocess.run(
        [str(binary), "--version"], capture_output=True, check=False, text=True
    )
    match = re.search(r"\d+\.\d+\.\d+\S*", result.stdout)
    if result.returncode or match is None:
        raise BiomeBinaryError(f"{binary} --version failed: {result.stderr.strip()}")
    return match.group(0)


def resolve(toplevel: pathlib.Path, main: pathlib.Path | None = None) -> pathlib.Path:
    """Returns the pinned binary, or raises BiomeBinaryError with what to run."""
    main = main_checkout(toplevel) if main is None else main
    candidates = [toplevel / BINARY]
    if main.resolve() != toplevel.resolve():
        candidates.append(main / BINARY)
    for binary in candidates:
        if not binary.is_file():
            continue
        pin = pinned_version(toplevel)
        version = installed_version(binary)
        if version != pin:
            raise BiomeBinaryError(
                f"{binary} is Biome {version} but package.json pins {pin}; "
                f"run bun install in {binary.parents[2]}"
            )
        return binary
    searched = ", ".join(str(binary) for binary in candidates)
    raise BiomeBinaryError(
        f"the pinned Biome is not installed (looked for {searched}); "
        f"run bun install in {main}"
    )


if __name__ == "__main__":
    try:
        print(resolve(pathlib.Path(sys.argv[1])))
    except (BiomeBinaryError, OSError, KeyError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
