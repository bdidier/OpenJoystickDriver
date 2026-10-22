"""Fail when a neutral target imports a module outside its allow-list.

The neutral targets are the core (`Sources/OpenJoystickDriverKit`), the command-line grammar
(`Sources/OpenJoystickDriverCLI`) and the executable's own files (`Sources/OpenJoystickDriver`).
They reach macOS only through protocols the core declares, such as `PlatformHost`. Code that
imports a macOS-only module lives in a platform target (`Sources/OpenJoystickDriverMacOSPlatform`,
`Sources/OpenJoystickDriverMacOSHost`) or below `Sources/OpenJoystickDriver/platform`.

Neutral means free of macOS device, security and application frameworks (IOKit, GameController,
CoreBluetooth, Security, AppKit, ServiceManagement, SystemExtensions). The core still uses Darwin
for POSIX calls and CryptoKit for hashing; both ship on every Apple platform the package declares,
so the core builds on Apple platforms only.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from collections.abc import Iterable

ROOT = pathlib.Path(__file__).resolve().parents[2]
KIT = "Sources/OpenJoystickDriverKit"
CLI = "Sources/OpenJoystickDriverCLI"
EXECUTABLE = "Sources/OpenJoystickDriver"
# The executable's host adapter directory: the only place a neutral target may import macOS modules.
ADAPTER_DIRECTORY = f"{EXECUTABLE}/platform"
ALLOWED_MODULES: dict[str, frozenset[str]] = {
    # Darwin and CryptoKit are Apple system libraries, not macOS frameworks; see the module text.
    KIT: frozenset({"CryptoKit", "Darwin", "Dispatch", "Foundation"}),
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


def skip_block_comment(text: str, index: int) -> int:
    """Return the index past a block comment whose body starts at `index`; comments nest."""
    depth = 1
    while index < len(text) and depth:
        pair = text[index : index + 2]
        if pair == "/*":
            depth += 1
            index += 2
        elif pair == "*/":
            depth -= 1
            index += 2
        else:
            index += 1
    return index


def skip_line_comment(text: str, index: int) -> int:
    end = text.find("\n", index)
    return len(text) if end < 0 else end


def skip_interpolation(text: str, index: int) -> int:
    """Return the index past the `)` closing an interpolation whose body starts at `index`."""
    depth = 1
    while index < len(text):
        pair = text[index : index + 2]
        opening = string_start(text, index) if text[index] in '#"' else None
        if pair == "/*":
            index = skip_block_comment(text, index + 2)
        elif pair == "//":
            index = skip_line_comment(text, index)
        elif opening:
            length, hashes, multiline = opening
            index = string_end(text, index + length, hashes, multiline)
        else:
            depth += {"(": 1, ")": -1}.get(text[index], 0)
            index += 1
            if depth == 0:
                return index
    return len(text)


def string_end(text: str, index: int, hashes: int, multiline: bool) -> int:
    """Return the index just past the string literal whose body starts at `index`."""
    closing = ('"' * 3 if multiline else '"') + "#" * hashes
    escape = "\\" + "#" * hashes
    while index < len(text):
        if text.startswith(escape + "(", index):
            index = skip_interpolation(text, index + len(escape) + 1)
        elif text.startswith(escape, index):
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
    triple-quoted strings, and raw `#"..."#` forms, including code inside `\\(...)` and
    `\\#(...)` interpolations. A `/*` or `//` inside a string neither starts a comment nor hides
    a later import.
    """
    out: list[str] = []
    index = 0
    while index < len(text):
        pair = text[index : index + 2]
        opening = string_start(text, index) if text[index] in '#"' else None
        if pair == "/*":
            end = skip_block_comment(text, index + 2)
        elif pair == "//":
            end = skip_line_comment(text, index)
        elif opening:
            length, hashes, multiline = opening
            end = string_end(text, index + length, hashes, multiline)
        else:
            out.append(text[index])
            index += 1
            continue
        out.append(blank(text[index:end]))
        index = end
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
    argparse.ArgumentParser(
        description="Fail when a neutral target imports a module outside its allow-list."
    ).parse_args(list(arguments))
    found = violations()
    for entry in found:
        print(f"import outside the neutral allow-list: {entry}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
