"""Fail when a neutral target imports a module outside its allow-list.

The neutral targets are the command-line grammar (`Sources/OpenJoystickDriverCLI`) and the
executable's own files (`Sources/OpenJoystickDriver`). They reach macOS only through the
`PlatformHost` protocol. Code that imports a macOS-only module lives in the host adapter target
(`Sources/OpenJoystickDriverMacOSHost`) or below `Sources/OpenJoystickDriver/platform`.
"""

from __future__ import annotations

import pathlib
import re
import sys
from collections.abc import Iterable

ROOT = pathlib.Path(__file__).resolve().parents[2]
CLI = "Sources/OpenJoystickDriverCLI"
EXECUTABLE = "Sources/OpenJoystickDriver"
# The executable's host adapter directory: the only place a neutral target may import macOS modules.
ADAPTER_DIRECTORY = f"{EXECUTABLE}/platform"
ALLOWED_MODULES: dict[str, frozenset[str]] = {
    CLI: frozenset(
        {
            "ArgumentParser",
            "Darwin",
            "Dispatch",
            "Foundation",
            "Glibc",
            "OpenJoystickDriverKit",
        }
    ),
    EXECUTABLE: frozenset(
        {"Dispatch", "Foundation", "OpenJoystickDriverCLI", "OpenJoystickDriverKit"}
    ),
}
IMPORT = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*import\s+(?:\w+\s+)?([A-Za-z_]\w*)")
CAN_IMPORT = re.compile(r"canImport\(\s*([A-Za-z_]\w*)\s*\)")


def strip_comments(text: str) -> str:
    """Blank out block comments (which nest in Swift), keeping every newline."""
    out: list[str] = []
    depth = 0
    index = 0
    while index < len(text):
        pair = text[index : index + 2]
        if pair == "/*":
            depth += 1
            index += 2
        elif pair == "*/" and depth:
            depth -= 1
            index += 2
        else:
            char = text[index]
            out.append(char if depth == 0 or char == "\n" else " ")
            index += 1
    return "".join(out)


def modules_on(line: str) -> list[str]:
    """Return the modules a line imports or probes with `canImport`."""
    found: list[str] = []
    for statement in line.split(";"):
        if statement.lstrip().startswith("//"):
            continue
        found.extend(match.group(1) for match in CAN_IMPORT.finditer(statement))
        imported = IMPORT.match(statement)
        if imported:
            found.append(imported.group(1))
    return found


def violations(root: pathlib.Path = ROOT) -> list[str]:
    found: list[str] = []
    for target, allowed in ALLOWED_MODULES.items():
        for path in sorted((root / target).rglob("*.swift")):
            relative = path.relative_to(root).as_posix()
            if relative.startswith(f"{ADAPTER_DIRECTORY}/"):
                continue
            lines = strip_comments(path.read_text(encoding="utf-8")).splitlines()
            for number, line in enumerate(lines, 1):
                for module in modules_on(line):
                    if module not in allowed:
                        found.append(f"{relative}:{number}: {module}")
    return found


def main(arguments: Iterable[str] = ()) -> int:
    del arguments
    found = violations()
    for entry in found:
        print(f"import outside the neutral allow-list: {entry}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
