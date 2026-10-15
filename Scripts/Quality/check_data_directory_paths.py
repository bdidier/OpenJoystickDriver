"""Fail when Swift sources build per-user data paths outside the DataDirectory port."""

from __future__ import annotations

import pathlib
import re
import sys
from collections.abc import Iterable

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = "Sources"
PORT_FILES = frozenset(
    {"Sources/OpenJoystickDriverKit/Storage/MacOSDataDirectory.swift"}
)
FORBIDDEN_PATTERNS = (
    r"\.urls\(for:",
    r"NSSearchPathForDirectoriesInDomains",
    r"\.applicationSupportDirectory",
    r"\.cachesDirectory",
    r"\.libraryDirectory",
    r"\.userDomainMask",
    r"NSHomeDirectory",
    r"homeDirectoryForCurrentUser",
    r"homeDirectory\(forUser",
    r"getpwuid",
    r"\btemporaryDirectory\b",
    r"NSTemporaryDirectory",
    r"DARWIN_USER_TEMP_DIR",
    r"\bconfstr\b",
    r"Application Support",
    r"\"Library/",
    r"\"/tmp",
    r"/var/folders",
)
FORBIDDEN = re.compile("(?:" + ")|(?:".join(FORBIDDEN_PATTERNS) + ")")


def violations(root: pathlib.Path = ROOT) -> list[str]:
    found: list[str] = []
    for path in sorted((root / SOURCES).rglob("*.swift")):
        relative = path.relative_to(root).as_posix()
        if relative in PORT_FILES:
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            match = FORBIDDEN.search(line)
            if match:
                found.append(f"{relative}:{number}: {match.group(0)}")
    return found


def main(arguments: Iterable[str] = ()) -> int:
    del arguments
    found = violations()
    for entry in found:
        print(f"path built outside the DataDirectory port: {entry}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
