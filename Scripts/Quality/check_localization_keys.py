"""Fail when a localization key and the en-US catalog disagree.

A key read by `OJDLocalized.*`, `CLILocalized.*`, `LocalizedStringResource(` or
`Localization().*` must exist in `Sources/OpenJoystickDriverKit/Resources/en-US.lproj`; a key built
from a literal prefix needs at least one catalog key with that prefix. A catalog key that no Swift
source under `Sources` reads also fails, unless `KEPT_WITHOUT_READER` names it and says why.

The catalog itself follows these rules:

- namespace: a key starts with one of the namespaces in `NAMESPACE_PATTERNS` and its segments are
  lowerCamelCase, except error codes;
- operating system words: a value in the English sources (`en-US`, `C`) names an operating system
  (`OS_WORDS`) only under `platform.`;
- specifiers: a value with more than one format specifier numbers every one (`%1$@`);
- comments: every en-US key has a translator comment directly above it;
- plurals: every `%#@name@` value has a `.stringsdict` entry in the same bundle, and each entry
  has the plural categories its locale needs (`PLURAL_CATEGORIES`).

`REKEY_PENDING` keeps the namespace, operating system word, specifier and comment rules from
failing while the catalog has the keys and values from before the re-key. The check prints how many
violations it is not enforcing. The re-key removes the flag.
"""

from __future__ import annotations

import plistlib
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOURCES_DIRECTORY = Path("Sources/OpenJoystickDriverKit/Resources")
CATALOG_DIRECTORY = Path("Sources/OpenJoystickDriverKit/Resources/en-US.lproj")
CALL = re.compile(
    r"\b(?:OJDLocalized\.(?:string|formatted|plural)|CLILocalized\.(?:text|format)"
    r"|LocalizedStringResource|(?:Localization\(\)|localization)\.(?:string|formatted|plural))\("
)
STRINGS_KEY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=', re.MULTILINE)
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


# True while the catalog has the keys, values and comments from before the namespace re-key. The
# namespace, operating system word, specifier and comment rules are reported but do not fail the
# check. The re-key removes this flag and `rekey_map.py`.
REKEY_PENDING = True

SEGMENT = r"(?:[a-z][a-zA-Z0-9]*|E\d{4})"
OPERATING_SYSTEMS = ("macos", "windows", "linux")
NAMESPACE_PATTERNS: dict[str, re.Pattern[str]] = {
    "term": re.compile(rf"term(?:\.{SEGMENT})+"),
    "action": re.compile(rf"action(?:\.{SEGMENT})+"),
    "status": re.compile(rf"status(?:\.{SEGMENT})+"),
    "a11y": re.compile(rf"a11y(?:\.{SEGMENT})+"),
    "notify": re.compile(rf"notify(?:\.{SEGMENT})+"),
    "ui": re.compile(rf"ui\.{SEGMENT}(?:\.{SEGMENT})+"),
    "ui.settings": re.compile(rf"ui\.settings\.{SEGMENT}(?:\.{SEGMENT})+"),
    "cli": re.compile(rf"cli\.{SEGMENT}\.{SEGMENT}(?:\.{SEGMENT})+"),
    "error": re.compile(rf"error\.E\d{{4}}(?:\.{SEGMENT})+"),
    "platform": re.compile(
        rf"platform\.(?:{'|'.join(OPERATING_SYSTEMS)})(?:\.{SEGMENT})+"
    ),
}
OS_WORDS = re.compile(
    r"\b(?:DriverKit|macOS|Mac|Apple|System Settings|Login Items|Finder|IOKit|systemextensionsctl"
    r"|launchd|Xcode)\b"
)
# A format specifier: optional position, flags, width, precision, length and conversion.
SPECIFIER = re.compile(
    r"%(?P<position>\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfeEgGcCsSpaAF]"
)
PLURAL_REFERENCE = re.compile(r"%#@[A-Za-z0-9_]+@")
# CLDR plural categories each shipped locale needs, by language.
PLURAL_CATEGORIES: dict[str, frozenset[str]] = {
    "ar": frozenset({"zero", "one", "two", "few", "many", "other"}),
    "ru": frozenset({"one", "few", "many", "other"}),
    "es": frozenset({"one", "many", "other"}),
    "fr": frozenset({"one", "many", "other"}),
    "it": frozenset({"one", "many", "other"}),
    "pt": frozenset({"one", "many", "other"}),
    **dict.fromkeys(("id", "ja", "ko", "th", "vi", "zh"), frozenset({"other"})),
    **dict.fromkeys(("C", "en", "de", "hi", "nl", "tr"), frozenset({"one", "other"})),
}
STRINGS_ENTRY = re.compile(
    r"(?:/\*(?P<comment>(?:(?!\*/).)*)\*/[ \t]*\n?)?"
    r'"(?P<key>(?:[^"\\]|\\.)*)"\s*=\s*"(?P<value>(?:[^"\\]|\\.)*)"\s*;',
    re.DOTALL,
)
STRINGSDICT_COMMENTED_KEY = re.compile(
    r"(?P<comment><!--(?:(?!-->).)*-->[ \t]*\n)?\t<key>(?P<key>[^<]+)</key>", re.DOTALL
)


@dataclass(frozen=True)
class StringsEntry:
    key: str
    value: str
    comment: str | None


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


def strings_entries(text: str) -> list[StringsEntry]:
    """Return each `"key" = "value";` of a `.strings` text with the comment directly above it."""
    return [
        StringsEntry(
            match["key"],
            match["value"],
            match["comment"].strip() if match["comment"] is not None else None,
        )
        for match in STRINGS_ENTRY.finditer(text)
    ]


def locale_directories(root: Path = ROOT) -> list[Path]:
    return sorted((root / RESOURCES_DIRECTORY).glob("*.lproj"))


def language(directory: Path) -> str:
    return directory.name.removesuffix(".lproj").split("-")[0]


def key_shape_problem(key: str) -> str | None:
    """Return why `key` is outside the namespaces, or None."""
    for namespace in ("ui.settings", "ui"):
        if key.startswith(namespace + "."):
            pattern = NAMESPACE_PATTERNS[namespace]
            return (
                None
                if pattern.fullmatch(key)
                else f"key {key!r} breaks the {namespace}. shape"
            )
    pattern = NAMESPACE_PATTERNS.get(key.split(".")[0])
    if pattern is None:
        return f"key {key!r} is outside the namespaces"
    return (
        None
        if pattern.fullmatch(key)
        else f"key {key!r} breaks the {key.split('.')[0]}. shape"
    )


def os_word_problem(key: str, value: str) -> str | None:
    """Return why `value` names an operating system outside `platform.`, or None."""
    word = OS_WORDS.search(value)
    if word is None or key.startswith("platform."):
        return None
    return f"{key!r}: the value names {word[0]!r} outside platform."


def specifier_problem(key: str, value: str) -> str | None:
    """Return why a value with several format specifiers leaves one without a position."""
    specifiers = [m for m in SPECIFIER.finditer(value.replace("%%", ""))]
    if len(specifiers) > 1 and any(m["position"] is None for m in specifiers):
        return f"{key!r}: several format specifiers need positions (%1$@)"
    return None


def comment_problem(entry: StringsEntry) -> str | None:
    return None if entry.comment else f"{entry.key!r}: no translator comment"


def plural_problems(directory: Path) -> list[str]:
    """Return the plural coverage problems of one bundle."""
    strings = strings_entries(
        (directory / "Localizable.strings").read_text(encoding="utf-8")
    )
    path = directory / "Localizable.stringsdict"
    plurals = plistlib.loads(path.read_bytes()) if path.exists() else {}
    needed = PLURAL_CATEGORIES[language(directory)]
    problems = [
        f"{directory.name}: {entry.key!r} takes a count but has no stringsdict entry"
        for entry in strings
        if PLURAL_REFERENCE.search(entry.value) and entry.key not in plurals
    ]
    for key, entry in plurals.items():
        variables = [item for item in entry.values() if isinstance(item, dict)]
        if not variables:
            problems.append(
                f"{directory.name}: stringsdict {key!r} has no plural variable"
            )
            continue
        for variable in variables:
            absent = sorted(needed - variable.keys())
            if absent:
                problems.append(
                    f"{directory.name}: stringsdict {key!r} lacks the plural forms {absent}"
                )
    return problems


def stringsdict_comment_problems(root: Path = ROOT) -> list[str]:
    text = (root / CATALOG_DIRECTORY / "Localizable.stringsdict").read_text(
        encoding="utf-8"
    )
    return [
        f"{match['key']!r}: no translator comment in the stringsdict"
        for match in STRINGSDICT_COMMENTED_KEY.finditer(text)
        if not match["comment"]
    ]


def stringsdict_values(root: Path = ROOT) -> dict[str, list[str]]:
    """Return the en-US stringsdict strings by key: the format key and each plural form."""
    plurals = plistlib.loads(
        (root / CATALOG_DIRECTORY / "Localizable.stringsdict").read_bytes()
    )
    return {
        key: [
            text
            for item in entry.values()
            for text in ([item] if isinstance(item, str) else item.values())
            if isinstance(text, str)
        ]
        for key, entry in plurals.items()
    }


def rekey_problems(root: Path = ROOT) -> list[str]:
    """Return the namespace, operating system word, specifier and comment violations."""
    problems: list[str] = []
    english = (root / CATALOG_DIRECTORY / "Localizable.strings").read_text(
        encoding="utf-8"
    )
    entries = strings_entries(english)
    for entry in entries:
        for problem in (
            key_shape_problem(entry.key),
            os_word_problem(entry.key, entry.value),
            specifier_problem(entry.key, entry.value),
            comment_problem(entry),
        ):
            if problem:
                problems.append(problem)
    for key, texts in stringsdict_values(root).items():
        for problem in (
            key_shape_problem(key),
            *(specifier_problem(key, t) for t in texts),
        ):
            if problem:
                problems.append(problem)
        problems.extend(
            p for p in stringsdict_comment_problems(root) if p.startswith(repr(key))
        )
    for name in ("C",):
        directory = root / RESOURCES_DIRECTORY / f"{name}.lproj"
        for entry in strings_entries(
            (directory / "Localizable.strings").read_text("utf-8")
        ):
            problem = os_word_problem(entry.key, entry.value)
            if problem:
                problems.append(f"C.lproj {problem}")
    for directory in locale_directories(root):
        if directory.name == "en-US.lproj":
            continue
        text = (directory / "Localizable.strings").read_text(encoding="utf-8")
        for entry in strings_entries(text):
            problem = specifier_problem(entry.key, entry.value)
            if problem:
                problems.append(f"{directory.name}: {problem}")
    return problems


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
    plurals = [
        problem
        for directory in locale_directories()
        for problem in plural_problems(directory)
    ]
    rekey = rekey_problems()
    for problem in plurals:
        print(problem)
    if REKEY_PENDING:
        print(
            f"re-key pending (REKEY_PENDING): {len(rekey)} namespace, operating system word, "
            "specifier and comment violation(s) are not enforced"
        )
    else:
        for problem in rekey:
            print(problem)
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
    enforced = plurals + ([] if REKEY_PENDING else rekey)
    if missing or unexplained or stale or enforced:
        print(
            f"error: {len(missing)} key(s) missing from en-US, {len(unexplained)} "
            f"key(s) with no reader, {len(stale)} stale kept entr(ies), "
            f"{len(enforced)} catalog rule violation(s)",
            file=sys.stderr,
        )
        return 1
    print("Every scannable localization key used in Swift exists in the en-US catalog.")
    print("Every en-US catalog key is read by Swift or kept with a reason.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
