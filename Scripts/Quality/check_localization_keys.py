"""Fail when a localization key and the en-US catalog disagree.

A key read by `OJDLocalized.*`, `CLILocalized.*`, `LocalizedStringResource(` or
`Localization().*` or passed to `.key(` must exist in `Sources/OpenJoystickDriverKit/Resources/en-US.lproj`; a key built
from a literal prefix needs at least one catalog key with that prefix. A catalog key that no Swift
source under `Sources` reads also fails, unless `KEPT_WITHOUT_READER` names it and says why.

The catalog itself follows these rules:

- namespace: a key starts with one of the namespaces in `NAMESPACE_PATTERNS` and its segments are
  lowerCamelCase, except error codes;
- operating system words: a value in the English sources (`en-US`, `C`) names an operating system
  (`OS_WORDS`) only under `platform.`;
- specifiers: a value with more than one format specifier numbers every one (`%1$@`);
- comments: every en-US key has a translator comment directly above it;
- plurals: every `%#@name@` value has a `.stringsdict` entry in the same bundle, each entry has the
  plural categories its language needs (`PLURAL_CATEGORIES_PATH`), and an en-US value with an integer
  count specifier (`%d`, `%lld`, `%1$lld`) has a `.stringsdict` entry unless `NOT_A_COUNT` names
  its key and says why the number is not a count.

`GATED_RULES` names each rule that does not fail yet and the task id that lifts it. The keys that
violate a gated rule are listed per rule in `localization-gated-keys.json`
(`{"rule": ["key", ...]}`). A gated rule does not fail on the keys listed under it and fails on
every other key, so a key cannot pick up a violation of a rule it is not listed under. The
check prints how many violations each gated rule holds back. A key listed under a rule it no longer
violates fails the check.

`--write-gated-keys` only removes entries: the keys that no longer violate their rule and the keys
that no longer exist. A violation not yet listed makes it fail, naming the key and the rule, and it
writes nothing. `--write-gated-keys --gate KEY RULE` (repeatable) adds exactly the named pairs. It
accepts only the `namespace` rule, and only for a key that violates it and belongs to a family a
pattern of `key_readers` reads (such as `error.E####`) whose other keys are all gated for
`namespace`: that reader builds the key from a code or prefix, so the key cannot take the shape
before the re-key. Any other addition is refused with the reason; `comment`, `osWord`, `specifier`
and `pluralCount` violations are fixed on the key itself.
Removing a rule from `GATED_RULES` enforces it everywhere.
"""

from __future__ import annotations

import json
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
    r"(?:\b(?:OJDLocalized\.(?:string|formatted|plural)|CLILocalized\.(?:text|format)"
    r"|LocalizedStringResource|(?:Localization\(\)|localization)\.(?:string|formatted|plural))"
    r"|\.key)\("
)
# An interpolated literal is a key lookup only where Swift passes it as a key: the first argument of
# a localization call or the value of a property named `...Key`. Other interpolated literals build
# identifiers, paths and messages.
KEY_POSITION = re.compile(
    CALL.pattern + r"\s*$|Key\s*:\s*String\s*\{\s*$",
)
# Interpolations whose values are a closed set, so the pattern names that set instead of any text.
EXACT_INTERPOLATIONS = {"error.\\(rawValue)": r"error\.E\d{4}"}
STRINGS_KEY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=', re.MULTILINE)
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


# Rules that do not fail on the keys in `GATED_KEYS_PATH`, each with the task that lifts it. Lifting
# a rule is deleting its entry.
GATED_RULES: dict[str, str] = {
    "namespace": "22.2",
    "osWord": "22.2",
    "specifier": "22.3",
    "comment": "22.3",
    "pluralCount": "22.3",
}
GATED_KEYS_PATH = Path("Scripts/Quality/localization-gated-keys.json")

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
# `Accessibility` is the permission or pane name: the whole value, or after the `>` of a pane path.
OS_WORDS = re.compile(
    r"\b(?:DriverKit|macOS|Mac|Apple|System Settings|Login Items|Finder|IOKit|systemextensionsctl"
    r"|launchd|Xcode|Input Monitoring|Privacy & Security|Dock|Terminal|TCC|codesign)\b"
    r"|^Accessibility$|>\s*Accessibility\b|\bAccessibility (?:permission|access)\b"
)
# A format specifier: optional position, flags, width, precision, length and conversion.
SPECIFIER = re.compile(
    r"%(?P<position>\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfeEgGcCsSpaAF]"
)
PLURAL_REFERENCE = re.compile(r"%#@[A-Za-z0-9_]+@")
COUNT_SPECIFIER = re.compile(r"%(?:\d+\$)?[-+ 0#]*\d*(?:hh|h|ll|l|q|z|t|j)?[dDiuU]")
# En-US keys whose integer specifier is not a count, each with the reason.
NOT_A_COUNT: dict[str, str] = {}
# Plural categories each language needs: one statement, read by the Swift LocalizationTests too. A
# bundle may carry more categories than its language needs.
PLURAL_CATEGORIES_PATH = Path("Resources/Localization/PluralCategories.json")
STRINGS_ENTRY = re.compile(
    r"(?:/\*(?P<comment>(?:(?!\*/).)*)\*/[ \t]*\n?)?"
    r'"(?P<key>(?:[^"\\]|\\.)*)"\s*=\s*"(?P<value>(?:[^"\\]|\\.)*)"\s*;',
    re.DOTALL,
)
STRINGSDICT_COMMENTED_KEY = re.compile(
    r"(?P<comment><!--(?:(?!-->).)*-->[ \t]*\n)?(?m:^)\t<key>(?P<key>[^<]+)</key>",
    re.DOTALL,
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
    return [text for _, text in string_literal_spans(source)]


def string_literal_spans(source: str) -> list[tuple[int, str]]:
    """Return (offset, text) for each string literal in `source`, interpolations included."""
    literals: list[tuple[int, str]] = []
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
            literals.append((index, source[index + 1 : end - 1]))
            index = end
        else:
            index += 1
    return literals


def interpolation_pattern(literal: str) -> re.Pattern[str] | None:
    """Return the pattern a key-building literal reads, or None without a literal prefix."""
    if "\\(" not in literal or "." not in literal.split("\\(")[0]:
        return None
    if literal in EXACT_INTERPOLATIONS:
        return re.compile(EXACT_INTERPOLATIONS[literal])
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


def key_readers(root: Path = ROOT) -> tuple[set[str], dict[str, re.Pattern[str]]]:
    """Return (literals Swift passes as keys, patterns of keys Swift builds from a prefix).

    A pattern is named by the source text that builds the key: `error.\\(rawValue)` or
    `profiles.gyro. + <text>`.
    """
    literals: set[str] = set()
    patterns: dict[str, re.Pattern[str]] = {}
    for path in reader_files(root):
        source = path.read_text(encoding="utf-8")
        for offset, literal in string_literal_spans(source):
            pattern = interpolation_pattern(literal)
            if pattern:
                line = source[source.rfind("\n", 0, offset) + 1 : offset]
                if KEY_POSITION.search(line):
                    patterns[literal] = pattern
            elif "\\(" not in literal:
                literals.add(literal)
    for literal in literals:
        if literal.endswith((".", "_")) and len(literal) > 3:
            patterns[f"{literal} + <text>"] = re.compile(re.escape(literal) + ".+")
    return literals, patterns


def unread_keys(root: Path = ROOT) -> tuple[list[str], dict[str, int]]:
    """Return (catalog keys no Swift source reads, keys read per pattern)."""
    keys = catalog_keys(root)
    literals, patterns = key_readers(root)
    unread: list[str] = []
    covered: dict[str, int] = {}
    for key in sorted(keys):
        if key in literals:
            continue
        matching = [
            text for text, pattern in patterns.items() if pattern.fullmatch(key)
        ]
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


def plural_categories(root: Path = ROOT) -> dict[str, frozenset[str]]:
    """Return the plural categories each language needs, from `PLURAL_CATEGORIES_PATH`."""
    data = json.loads((root / PLURAL_CATEGORIES_PATH).read_text(encoding="utf-8"))
    return {name: frozenset(categories) for name, categories in data.items()}


def plural_problems(directory: Path) -> list[str]:
    """Return the plural coverage problems of one bundle."""
    strings = strings_entries(
        (directory / "Localizable.strings").read_text(encoding="utf-8")
    )
    path = directory / "Localizable.stringsdict"
    plurals = plistlib.loads(path.read_bytes()) if path.exists() else {}
    needed = plural_categories()[language(directory)]
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


def stringsdict_uncommented_keys(root: Path = ROOT) -> set[str]:
    """Return the en-US stringsdict keys without a translator comment above them."""
    text = (root / CATALOG_DIRECTORY / "Localizable.stringsdict").read_text(
        encoding="utf-8"
    )
    matches = list(STRINGSDICT_COMMENTED_KEY.finditer(text))
    top_level = set(plistlib.loads(text.encode("utf-8")))
    if {match["key"] for match in matches} != top_level:
        raise ValueError(
            "the en-US stringsdict has top-level keys the comment scan does not match: "
            f"{sorted(top_level ^ {match['key'] for match in matches})}"
        )
    return {match["key"] for match in matches if not match["comment"]}


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


@dataclass(frozen=True)
class RuleProblem:
    key: str
    message: str


def count_specifier_problem(entry: StringsEntry, plurals: set[str]) -> str | None:
    """Return why an integer specifier has no plural entry, or None."""
    if (
        entry.key in plurals
        or entry.key in NOT_A_COUNT
        or not COUNT_SPECIFIER.search(entry.value.replace("%%", ""))
    ):
        return None
    return (
        f"{entry.key!r}: an integer specifier needs a stringsdict entry, "
        "or a NOT_A_COUNT reason"
    )


def rule_problems(root: Path = ROOT) -> dict[str, list[RuleProblem]]:
    """Return the violations of the gateable rules by rule name."""
    found: dict[str, list[RuleProblem]] = {
        "namespace": [],
        "osWord": [],
        "specifier": [],
        "comment": [],
        "pluralCount": [],
    }

    def add(rule: str, key: str, message: str | None, prefix: str = "") -> None:
        if message:
            found[rule].append(RuleProblem(key, prefix + message))

    directory = root / CATALOG_DIRECTORY
    entries = strings_entries((directory / "Localizable.strings").read_text("utf-8"))
    plurals = plistlib.loads((directory / "Localizable.stringsdict").read_bytes())
    uncommented = stringsdict_uncommented_keys(root)
    for entry in entries:
        add("namespace", entry.key, key_shape_problem(entry.key))
        add("osWord", entry.key, os_word_problem(entry.key, entry.value))
        add("specifier", entry.key, specifier_problem(entry.key, entry.value))
        add("comment", entry.key, comment_problem(entry))
        add("pluralCount", entry.key, count_specifier_problem(entry, set(plurals)))
    for key, texts in stringsdict_values(root).items():
        add("namespace", key, key_shape_problem(key))
        for text in texts:
            add("specifier", key, specifier_problem(key, text))
        if key in uncommented:
            add("comment", key, f"{key!r}: no translator comment in the stringsdict")
    for name in ("C",):
        for entry in strings_entries(
            (
                root / RESOURCES_DIRECTORY / f"{name}.lproj" / "Localizable.strings"
            ).read_text("utf-8")
        ):
            add(
                "osWord",
                entry.key,
                os_word_problem(entry.key, entry.value),
                f"{name}.lproj ",
            )
    for locale in locale_directories(root):
        if locale.name == "en-US.lproj":
            continue
        text = (locale / "Localizable.strings").read_text(encoding="utf-8")
        for entry in strings_entries(text):
            add(
                "specifier",
                entry.key,
                specifier_problem(entry.key, entry.value),
                f"{locale.name}: ",
            )
    return found


def gated_keys(root: Path = ROOT) -> dict[str, set[str]]:
    """Return, per gated rule, the catalog keys the rule does not fail on."""
    if not GATED_RULES:
        return {}
    data = json.loads((root / GATED_KEYS_PATH).read_text(encoding="utf-8"))
    return {rule: set(data.get(rule, [])) for rule in GATED_RULES}


def family_problem(
    key: str, root: Path, gated: dict[str, set[str]], adding: set[str]
) -> str | None:
    """Return why `key` is not in a key family whose reader blocks the namespace shape, or None.

    A family is the keys one pattern of `key_readers` reads. It blocks the shape when every other
    key of the family is gated for `namespace` and at least one such key already exists outside the
    keys being added, so a family cannot be invented and gated in one change: the reader builds the key from a code or prefix, so
    the key cannot take the shape before the re-key without breaking the reader.
    """
    _, patterns = key_readers(root)
    matching = [text for text, pattern in patterns.items() if pattern.fullmatch(key)]
    if not matching:
        return f"{key!r} is read by no pattern, so it can take the namespace shape; rename it"
    keys = catalog_keys(root)
    namespace = gated.get("namespace", set())
    for text in matching:
        pattern = patterns[text]
        ungated = sorted(
            member
            for member in keys
            if pattern.fullmatch(member)
            and member not in adding
            and member not in namespace
        )
        if ungated:
            return (
                f"{key!r}: the family read by {text!r} has the ungated member "
                f"{ungated[0]!r}, so the family can take the namespace shape"
            )
        if not any(
            pattern.fullmatch(member) and member not in adding and member in namespace
            for member in keys
        ):
            return (
                f"{key!r}: the family read by {text!r} has no gated key besides the ones "
                "added, so it is not an existing family"
            )
    return None


def update_gated_keys(
    root: Path = ROOT, additions: list[tuple[str, str]] | None = None
) -> tuple[dict[str, list[str]], list[str]]:
    """Return (the new gated keys per rule, the reasons the update is refused).

    The update drops the keys that no longer violate their rule or no longer exist. It adds only
    the `additions` that `--gate` names, each a `namespace` key of a fully gated family. A key that
    violates a rule without being listed is refused with the key and the rule.
    """
    additions = additions or []
    found = rule_problems(root)
    violating = {rule: {p.key for p in found[rule]} for rule in GATED_RULES}
    current = gated_keys(root)
    refused: list[str] = []
    accepted: set[tuple[str, str]] = set()
    adding = {key for key, rule in additions if rule == "namespace"}
    for key, rule in additions:
        if rule not in GATED_RULES:
            refused.append(f"--gate {key} {rule}: {rule!r} is not a gated rule")
        elif rule != "namespace":
            refused.append(
                f"--gate {key} {rule}: only namespace can be gated; fix the key's {rule} violation"
            )
        elif key not in violating[rule]:
            refused.append(f"--gate {key} {rule}: the key violates no {rule} rule")
        else:
            reason = family_problem(key, root, current, adding)
            if reason:
                refused.append(f"--gate {key} {rule}: {reason}")
            else:
                accepted.add((key, rule))
    kept = {rule: current[rule] & violating[rule] for rule in GATED_RULES}
    for key, rule in accepted:
        kept[rule].add(key)
    for rule in GATED_RULES:
        refused.extend(
            f"{key!r} would need gating for the {rule} rule; fix the key instead"
            for key in sorted(violating[rule] - kept[rule])
        )
    return {rule: sorted(keys) for rule, keys in kept.items()}, refused


def write_gated_keys(
    root: Path = ROOT, additions: list[tuple[str, str]] | None = None
) -> list[str]:
    """Write `update_gated_keys` to `GATED_KEYS_PATH` unless it refuses; return the refusals."""
    data, refused = update_gated_keys(root, additions)
    if not refused:
        text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
        (root / GATED_KEYS_PATH).write_text(text, encoding="utf-8")
    return refused


def parse_gate_arguments(arguments: list[str]) -> list[tuple[str, str]] | None:
    """Return the (key, rule) pairs of `--write-gated-keys [--gate KEY RULE]...`, or None."""
    if not arguments or arguments[0] != "--write-gated-keys":
        return None
    rest = arguments[1:]
    pairs: list[tuple[str, str]] = []
    while rest:
        if rest[0] != "--gate" or len(rest) < 3:
            return None
        pairs.append((rest[1], rest[2]))
        rest = rest[3:]
    return pairs


def rule_report(
    found: dict[str, list[RuleProblem]], gated: dict[str, set[str]]
) -> tuple[list[str], list[str], list[str]]:
    """Return (failing messages, held-back notes, keys listed under a rule they do not violate)."""
    failing: list[str] = []
    held: list[str] = []
    stale: list[str] = []
    for rule, problems in found.items():
        task = GATED_RULES.get(rule)
        listed = gated.get(rule, set()) if task else set()
        held_back = [p for p in problems if p.key in listed]
        failing.extend(p.message for p in problems if p not in held_back)
        if held_back:
            held.append(
                f"gated rule {rule}: {len(held_back)} violation(s) held back until "
                f"task {task}"
            )
        used = {p.key for p in held_back}
        stale.extend(
            f"gated key {key!r} violates no {rule} rule; remove it with --write-gated-keys"
            for key in sorted(listed - used)
        )
    return failing, held, stale


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


def main(arguments: list[str] | None = None) -> int:
    if arguments:
        additions = parse_gate_arguments(arguments)
        if additions is None:
            print(
                "usage: check_localization_keys.py [--write-gated-keys [--gate KEY RULE]...]",
                file=sys.stderr,
            )
            return 2
        refused = write_gated_keys(ROOT, additions)
        for reason in refused:
            print(reason, file=sys.stderr)
        return 1 if refused else 0
    missing, unscannable = check()
    unread, covered = unread_keys()
    unexplained = [key for key in unread if key not in KEPT_WITHOUT_READER]
    stale = stale_kept(unread, catalog_keys())
    plurals = [
        problem
        for directory in locale_directories()
        for problem in plural_problems(directory)
    ]
    failing, held, stale_gated = rule_report(rule_problems(), gated_keys())
    for problem in plurals + failing:
        print(problem)
    for note in held + stale_gated:
        print(note)
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
    enforced = plurals + failing + stale_gated
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
    raise SystemExit(main(sys.argv[1:]))
