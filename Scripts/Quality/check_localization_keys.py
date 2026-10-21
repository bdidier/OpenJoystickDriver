"""Fail when a localization key used in Swift code is missing from the en-US catalog.

English text lives only in `Sources/OpenJoystickDriverKit/Resources/en-US.lproj`. Call sites pass a key
and nothing else, so a key that is absent from that catalog would render as the raw key.

The scan reads the first argument of `OJDLocalized.*`, `CLILocalized.*`, `LocalizedStringResource(`,
and `Localization().*` / `localization.*` calls. A literal key must exist exactly. A ternary of
literals must have both keys. A key built from a literal prefix, such as `"error.\\(rawValue)"` or
`"profiles.stick." + key`, must have at least one catalog key with that prefix. Other dynamic keys
cannot be checked and are listed.

The scan also fails on a catalog key that no Swift source under `Sources` reads. A key is read
when its literal is any string literal of those files, so keys held in tables, enum properties and
`.key(...)` wrappers count. A string literal with an interpolation after a literal prefix, such as
`"error.\\(rawValue)"` or `"area.\\(rawValue).title"`, reads every key it matches, each
interpolation standing for one key segment (no dot). A literal prefix ending in `.` or `_`, such as
`"profiles.stick." + key`, reads every key with that prefix. `KEPT_WITHOUT_READER` names each key
kept without a reader and why. The scan prints every pattern that reads keys, with the key count.
"""

from __future__ import annotations

import plistlib
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG_DIRECTORY = Path("Sources/OpenJoystickDriverKit/Resources/en-US.lproj")
CALL = re.compile(
    r"\b(?:OJDLocalized\.(?:string|formatted|plural)|CLILocalized\.(?:text|format)"
    r"|LocalizedStringResource|(?:Localization\(\)|localization)\.(?:string|formatted|plural))\("
)
STRINGS_KEY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=', re.MULTILINE)
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


# Catalog keys no Swift source reads but that stay, each with its reason.
KEPT_WITHOUT_READER: dict[str, str] = {}


@dataclass(frozen=True)
class KeyUse:
    path: str
    line: int
    expression: str


def skip_string(source: str, index: int) -> int:
    """Return the index after the string literal that starts at `index`."""
    index += 1
    while True:
        character = source[index]
        if character == "\\":
            if source[index + 1] == "(":
                index = skip_group(source, index + 1)
            else:
                index += 2
        elif character == '"':
            return index + 1
        else:
            index += 1


def skip_group(source: str, index: int) -> int:
    """Return the index after the bracket group that starts at `index`."""
    depth = 0
    while True:
        character = source[index]
        if character == '"':
            index = skip_string(source, index)
            continue
        if source.startswith("//", index):
            index = source.index("\n", index)
            continue
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1


def first_argument(source: str, open_index: int) -> str:
    """Return the text of the first argument of the call whose `(` is at `open_index`."""
    depth = 0
    index = open_index + 1
    while True:
        character = source[index]
        if character == '"':
            index = skip_string(source, index)
            continue
        if source.startswith("//", index):
            index = source.index("\n", index)
            continue
        if character in "([{":
            depth += 1
        elif character in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif character == "," and depth == 0:
            break
        index += 1
    return source[open_index + 1 : index].strip()


def string_literals(source: str) -> list[str]:
    """Return the text of each string literal in `source`, interpolations included."""
    literals: list[str] = []
    index = 0
    while index < len(source):
        if source.startswith("//", index):
            newline = source.find("\n", index)
            index = len(source) if newline < 0 else newline
        elif source.startswith("/*", index):
            end = source.find("*/", index + 2)
            index = len(source) if end < 0 else end + 2
        elif source.startswith('"""', index):
            end = source.find('"""', index + 3)
            index = len(source) if end < 0 else end + 3
        elif source.startswith('#"', index):
            end = source.find('"#', index + 2)
            index = len(source) if end < 0 else end + 2
        elif source[index] == '"':
            end = skip_string(source, index)
            literals.append(source[index + 1 : end - 1])
            index = end
        else:
            index += 1
    return literals


def interpolation_pattern(literal: str) -> re.Pattern[str] | None:
    """Return the pattern a key-building literal reads, or None without a literal prefix."""
    if "\\(" not in literal or "." not in literal.split("\\(")[0]:
        return None
    pattern = ""
    index = 0
    while index < len(literal):
        if literal.startswith("\\(", index):
            pattern += "[^.]+"
            index = skip_group(literal, index + 1)
        else:
            pattern += re.escape(literal[index])
            index += 1
    return re.compile(pattern)


def key_arguments(source: str) -> list[tuple[int, str]]:
    """Return (line, first-argument text) for each localization call in `source`."""
    return [
        (
            source.count("\n", 0, match.start()) + 1,
            first_argument(source, match.end() - 1),
        )
        for match in CALL.finditer(source)
    ]


def catalog_keys(root: Path = ROOT) -> set[str]:
    """Return the keys of the en-US `.strings` and `.stringsdict` catalogs."""
    directory = root / CATALOG_DIRECTORY
    strings = (directory / "Localizable.strings").read_text(encoding="utf-8")
    keys = set(STRINGS_KEY.findall(strings))
    keys.update(plistlib.loads((directory / "Localizable.stringsdict").read_bytes()))
    return keys


def problems(expression: str, keys: set[str]) -> str | None:
    """Return why `expression` names a missing key, or None when it is fine or unscannable."""
    literals = LITERAL.findall(expression)
    if re.fullmatch(r'"[^"\\]*"', expression):
        return None if literals[0] in keys else f"missing key {literals[0]!r}"
    ternary = re.search(r'\?\s*"([^"\\]*)"\s*:\s*"([^"\\]*)"', expression)
    if ternary:
        absent = [key for key in ternary.groups() if key not in keys]
        return f"missing key {absent[0]!r}" if absent else None
    prefix = re.match(r'"([^"\\]*)(?:\\\(|"\s*\+)', expression)
    if prefix and prefix.group(1):
        if any(key.startswith(prefix.group(1)) for key in keys):
            return None
        return f"no key starts with {prefix.group(1)!r}"
    return None


def tracked_swift_files(root: Path = ROOT) -> list[Path]:
    output = subprocess.run(
        [
            "git",
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
            "*.swift",
        ],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [
        root / name for name in output.split("\0") if name and (root / name).exists()
    ]


def reader_files(root: Path = ROOT) -> list[Path]:
    """Return the Swift files whose string literals count as readers: all of `Sources`."""
    return [
        path
        for path in tracked_swift_files(root)
        if path.relative_to(root).parts[0] == "Sources"
    ]


def unread_keys(root: Path = ROOT) -> tuple[list[str], dict[str, int]]:
    """Return (catalog keys no Swift source reads, keys read per pattern)."""
    keys = catalog_keys(root)
    literals: set[str] = set()
    patterns: dict[str, re.Pattern[str]] = {}
    for path in reader_files(root):
        for literal in string_literals(path.read_text(encoding="utf-8")):
            pattern = interpolation_pattern(literal)
            if pattern:
                patterns[literal] = pattern
            elif "\\(" not in literal:
                literals.add(literal)
    prefixes = {
        literal
        for literal in literals
        if literal.endswith((".", "_")) and len(literal) > 3
    }
    unread: list[str] = []
    covered: dict[str, int] = {}
    for key in sorted(keys):
        if key in literals:
            continue
        matching = [t for t, pattern in patterns.items() if pattern.fullmatch(key)]
        matching += [f"{p} + <text>" for p in prefixes if key.startswith(p)]
        for text in matching:
            covered[text] = covered.get(text, 0) + 1
        if not matching:
            unread.append(key)
    return unread, covered


def stale_kept(unread: list[str], keys: set[str]) -> list[str]:
    """Return why a `KEPT_WITHOUT_READER` entry no longer holds."""
    return [
        f"kept key {key!r} "
        + ("is not in the catalog" if key not in keys else "has a reader")
        for key in sorted(KEPT_WITHOUT_READER)
        if key not in keys or key not in unread
    ]


def check(root: Path = ROOT) -> tuple[list[tuple[KeyUse, str]], list[KeyUse]]:
    """Return (missing keys with reasons, call sites whose key cannot be scanned)."""
    keys = catalog_keys(root)
    missing: list[tuple[KeyUse, str]] = []
    unscannable: list[KeyUse] = []
    for path in tracked_swift_files(root):
        relative = path.relative_to(root).as_posix()
        for line, expression in key_arguments(path.read_text(encoding="utf-8")):
            use = KeyUse(relative, line, expression)
            reason = problems(expression, keys)
            if reason:
                missing.append((use, reason))
            elif not LITERAL.search(expression):
                unscannable.append(use)
    return missing, unscannable


def main() -> int:
    missing, unscannable = check()
    unread, covered = unread_keys()
    unexplained = [key for key in unread if key not in KEPT_WITHOUT_READER]
    stale = stale_kept(unread, catalog_keys())
    for use, reason in missing:
        print(f"{use.path}:{use.line}: {reason} in the en-US catalog")
    for use in unscannable:
        print(f"{use.path}:{use.line}: key not scanned: {use.expression}")
    for key in unexplained:
        print(f"{key}: no Swift source reads this catalog key")
    for problem in stale:
        print(problem)
    for key, reason in KEPT_WITHOUT_READER.items():
        print(f"kept without reader: {key}: {reason}")
    for text, count in sorted(covered.items()):
        print(f"read by pattern: {text} ({count} keys)")
    if missing or unexplained or stale:
        print(
            f"error: {len(missing)} key(s) missing from en-US, {len(unexplained)} "
            f"key(s) with no reader, {len(stale)} stale kept entr(ies)",
            file=sys.stderr,
        )
        return 1
    print("Every scannable localization key used in Swift exists in the en-US catalog.")
    print("Every en-US catalog key is read by Swift or kept with a reason.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
