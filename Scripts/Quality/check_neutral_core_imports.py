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


def blank(text: str) -> str:
    """Replace everything but newlines with spaces."""
    return "".join(char if char == "\n" else " " for char in text)


def string_start(text: str, index: int) -> tuple[int, int, bool] | None:
    """Return (opening length, hash count, multiline) for a string literal opening at `index`."""
    hashes = 0
    while text[index + hashes : index + hashes + 1] == "#":
        hashes += 1
    after = index + hashes
    if text[after : after + 1] != '"':
        return None
    multiline = text[after : after + 3] == '"' * 3
    return hashes + (3 if multiline else 1), hashes, multiline


def string_end(text: str, index: int, hashes: int, multiline: bool) -> int:
    """Return the index just past the string literal whose body starts at `index`."""
    closing = ('"' * 3 if multiline else '"') + "#" * hashes
    escape = "\\" + "#" * hashes
    while index < len(text):
        if text.startswith(escape, index):
            index += len(escape) + 1
        elif text.startswith(closing, index):
            return index + len(closing)
        elif text[index] == "\n" and not multiline:
            return index
        else:
            index += 1
    return len(text)


def strip_comments(text: str) -> str:
    """Blank out comments and string literal contents, keeping every newline.

    Block comments nest, as in Swift. String forms handled are `"..."` with escapes, multiline
    `\"\"\"...\"\"\"`, and raw `#"..."#` forms, so a `/*` or `//` inside a string neither
    starts a comment nor hides a later import.
    """
    out: list[str] = []
    index = 0
    depth = 0
    while index < len(text):
        pair = text[index : index + 2]
        if depth:
            if pair == "/*":
                depth += 1
                step = 2
            elif pair == "*/":
                depth -= 1
                step = 2
            else:
                step = 1
            out.append(blank(text[index : index + step]))
            index += step
        elif pair == "/*":
            depth = 1
            out.append("  ")
            index += 2
        elif pair == "//":
            end = text.find("\n", index)
            end = len(text) if end < 0 else end
            out.append(blank(text[index:end]))
            index = end
        elif text[index] in '#"' and (opening := string_start(text, index)):
            length, hashes, multiline = opening
            end = string_end(text, index + length, hashes, multiline)
            out.append(blank(text[index:end]))
            index = end
        else:
            out.append(text[index])
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
