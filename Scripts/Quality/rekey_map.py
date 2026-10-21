"""Build the old-to-new localization key map for the namespace re-key.

The map is one-off. It lives at `openspec/changes/platform-neutral-redesign/` until task 22.2 has
applied the re-key; the map, this script and `test_rekey_map.py` are deleted right after 22.2.
Task 22.2 renames each key in three places, in one change:

- every `*.lproj` bundle, without touching a value;
- every Swift call site that names a key, including the dynamic prefixes that Swift builds a
  key from (`error.\\(rawValue)` becomes `error.\\(rawValue).message`, `area.\\(rawValue).title`
  becomes `ui.sidebar.\\(rawValue).title`);
- `Scripts/Quality/generate_error_codes.py` and `ErrorCodeTests`, which read the error code keys.

The strings keep changing until the tree is quiet, so regenerate right before the re-key:

    python3 -m Scripts.Quality.rekey_map --write

Without `--write` the script fails when the file differs from what the current en-US catalog and
the rules below produce. The rules:

- A key maps to the namespace of its screen or role (`AREA_PREFIXES`, `common`, `keyboard`,
  `settings`, `cli`, `error`), and every segment becomes lowerCamelCase. The menu bar extra
  (`menuBar`) maps to `ui.extra`, and the main menu (`mainMenu.<menu>.<item>`) to
  `ui.menu.<menu>.<item>`. A key already in `term.` or `ui.` keeps its name.
- A `cli` key becomes `cli.<group>.<command>.<leaf>` when `<command>` is a command of the group in
  the command tree under `Sources/OpenJoystickDriverCLI` (`commandName:` values, grouped by the
  directory under `Commands`). Every other key of the group becomes `cli.<group>.group.<leaf>`,
  and the cross-command groups `error`, `option`, `document` and `help` use the group `shared`.
- A value that names an operating system (`OS_WORDS`) moves under `platform.macos.`, with the
  namespaced key as the path, except when Swift builds the key from a prefix (a key in
  `error.`, `area.`, `profiles.stick.` and the other patterns `check_localization_keys` lists as
  `read by pattern`): such a key keeps the prefix, so the call site keeps one shape, and is listed
  under `neutralTextRequired` for task 22.2 to reword. Splitting any other such value into a
  neutral text and a platform text is a content change, not part of the re-key.
- Keys are not merged. `duplicateValues` lists the English values shared by several keys, as
  candidates for a later merge.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
from collections import defaultdict
from pathlib import Path

from Scripts.Quality import check_localization_keys as keys
from Scripts.Quality.biome_format import format_json

ROOT = Path(__file__).resolve().parents[2]
MAP_PATH = Path(
    "openspec/changes/platform-neutral-redesign/localization-rekey-map.json"
)

# Old first segment -> new leading segments.
AREA_PREFIXES: dict[str, tuple[str, ...]] = {
    "access": ("ui", "access"),
    "activity": ("ui", "activity"),
    "banner": ("ui", "banner"),
    "capture": ("ui", "capture"),
    "console": ("ui", "console"),
    "debug": ("ui", "debug"),
    "developer": ("ui", "developer"),
    "inputTest": ("ui", "inputTest"),
    "library": ("ui", "library"),
    "mainWindow": ("ui", "mainWindow"),
    "mapping": ("ui", "mapping"),
    "motion": ("ui", "motion"),
    "permissions": ("ui", "permissions"),
    "profiles": ("ui", "profiles"),
    "setup": ("ui", "setup"),
    "shortcuts": ("ui", "shortcuts"),
    "virtualProfile": ("ui", "virtualProfile"),
    "controllers": ("ui", "controllers"),
    "area": ("ui", "sidebar"),
    "app": ("term", "app"),
    "notifications": ("notify",),
    "a11y": ("a11y",),
    "status": ("status",),
    "menuBar": ("ui", "extra"),
    "menu": ("ui", "menu"),
}

COMMON_NAMESPACE: dict[str, str] = {
    **dict.fromkeys(
        [
            "ok",
            "refresh",
            "tryAgain",
            "cancel",
            "save",
            "create",
            "delete",
            "dismiss",
            "reload",
            "keepEditing",
            "clear",
            "request",
            "addAssignment",
            "removeAssignment",
            "adjust",
            "duplicate",
            "deactivate",
            "setActive",
            "apply",
            "add",
            "remove",
            "reset",
            "stop",
            "export",
            "copyAll",
            "done",
        ],
        "action",
    ),
    **dict.fromkeys(
        [
            "unavailable",
            "selected",
            "notSelected",
            "notRequested",
            "none",
            "needsAttention",
            "failed",
            "available",
            "disabled",
        ],
        "status",
    ),
    **dict.fromkeys(
        [
            "status",
            "serialNumber",
            "protocol",
            "profileName",
            "outputEndpoint",
            "inputRead",
            "inputInject",
            "inputEndpoint",
            "destination",
            "controller",
            "assignments",
            "assignment",
            "keyboardPointer",
        ],
        "term",
    ),
}

KEY_NAMES = frozenset(
    [
        "upArrow",
        "downArrow",
        "leftArrow",
        "rightArrow",
        "tab",
        "space",
        "shift",
        "return",
        "pageUp",
        "pageDown",
        "meta",
        "forwardDelete",
        "delete",
        "escape",
        "control",
        "capsLock",
        "alt",
    ]
)

# `settings.<x>` entries that belong to a pane other than General.
NOTIFICATIONS_PANE = re.compile(
    r"notification|Notifications$|Short$|^requestAccess$|^accessReadiness$|^testNotification$"
)
ADVANCED_PANE = re.compile(
    r"^(?:developerTools|enableDeveloperTools|error|unreadable|discard)"
)

SHARED_CLI_GROUPS = frozenset({"error", "option", "document", "help"})
ERROR_CODE_SOURCE = Path("Sources/OpenJoystickDriverKit/Errors/ErrorCode.swift")
ERROR_CODE_CASE = re.compile(r'case\s+\w+\s*=\s*"(E\d{4})"')
CLI_COMMANDS_DIRECTORY = Path("Sources/OpenJoystickDriverCLI/Commands")
COMMAND_NAME = re.compile(r'commandName:\s*"([^"]+)"')


def command_tree(root: Path = ROOT) -> dict[str, frozenset[str]]:
    """Return the commands of each group, in old key spelling, from the CLI sources.

    A group is a directory under `Commands`; its commands are the `commandName:` values in it,
    except the group's own name.
    """
    tree: dict[str, frozenset[str]] = {}
    for directory in sorted((root / CLI_COMMANDS_DIRECTORY).iterdir()):
        if not directory.is_dir():
            continue
        group = re.sub(r"(?<=[a-z])(?=[A-Z])", "_", directory.name).lower()
        names = {
            name.replace("-", "_")
            for path in directory.rglob("*.swift")
            for name in COMMAND_NAME.findall(path.read_text(encoding="utf-8"))
        }
        tree[group] = frozenset(names - {group})
    return tree


def camel(segment: str) -> str:
    """Return `segment` with snake_case turned into lowerCamelCase."""
    head, *rest = segment.split("_")
    return head + "".join(part[:1].upper() + part[1:] for part in rest)


def segments(parts: list[str]) -> list[str]:
    return [camel(part) for part in parts]


def join_leaf(parts: list[str]) -> str:
    """Join several old segments into one lowerCamelCase leaf segment."""
    words = segments(parts)
    return words[0] + "".join(word[:1].upper() + word[1:] for word in words[1:])


def cli_key(parts: list[str], tree: dict[str, frozenset[str]]) -> list[str]:
    """Return the new segments of the `cli` key whose old segments, without `cli`, are `parts`."""
    group = parts[0]
    rest = parts[1:]
    if group in SHARED_CLI_GROUPS:
        return ["cli", "shared", group, join_leaf(rest)]
    if not rest:
        raise ValueError("cli key without a leaf")
    head = rest[0]
    commands = tree.get(group, frozenset())
    # A key spelled in the new lowerCamelCase names its command the same way.
    if len(rest) > 1 and (
        head in commands or head in {camel(name) for name in commands}
    ):
        return ["cli", camel(group), camel(head), join_leaf(rest[1:])]
    return ["cli", camel(group), "group", join_leaf(rest)]


def settings_key(parts: list[str]) -> list[str]:
    rest = parts[1:]
    if parts[0] == "settingsPane":
        return ["ui", "settings", camel(rest[0]), join_leaf(rest[1:])]
    if rest[0] == "commandLineTool":
        tail = ["tool"] + rest[1:]
        return ["ui", "settings", "commandLine", join_leaf(tail)]
    name = rest[0]
    if ADVANCED_PANE.search(name):
        pane = "advanced"
    elif NOTIFICATIONS_PANE.search(name):
        pane = "notifications"
    else:
        pane = "general"
    return ["ui", "settings", pane, join_leaf(rest)]


def new_segments(old: str, tree: dict[str, frozenset[str]]) -> list[str]:
    parts = old.split(".")
    top = parts[0]
    rest = parts[1:]
    if top in ("term", "ui"):
        return parts
    if top == "cli":
        return cli_key(rest, tree)
    if top in ("settings", "settingsPane"):
        return settings_key(parts)
    if top == "a11y" and rest[0] == "settingsPane":
        return ["a11y", "settingsPane", join_leaf(rest[1:])]
    if top == "mainMenu":
        return ["ui", "menu", camel(rest[0]), *(segments(rest[1:]) or ["title"])]
    if top == "common":
        return [COMMON_NAMESPACE[rest[0]], join_leaf(rest)]
    if top == "keyboard":
        namespace = ("term", "key") if rest[0] in KEY_NAMES else ("ui", "keyboard")
        return [*namespace, join_leaf(rest)]
    if top == "error":
        if re.fullmatch(r"E\d{4}", rest[0]):
            return ["error", rest[0], "message"]
        return ["ui", "error", join_leaf(rest)]
    if top in AREA_PREFIXES:
        return [*AREA_PREFIXES[top], *segments(rest)]
    raise ValueError(f"no rule for the first segment of {old!r}")


def new_key(
    old: str, value: str, tree: dict[str, frozenset[str]], pattern_read: bool
) -> str:
    key = new_segments(old, tree)
    if keys.OS_WORDS.search(value) and not pattern_read:
        key = ["platform", "macos", *key]
    return ".".join(key)


def english_values(root: Path) -> dict[str, str]:
    """Return the en-US key -> value map; a plural key has the value of its `other` form."""
    directory = root / keys.CATALOG_DIRECTORY
    values = {
        entry.key: entry.value
        for entry in keys.strings_entries(
            (directory / "Localizable.strings").read_text("utf-8")
        )
    }
    for key, entry in plistlib.loads(
        (directory / "Localizable.stringsdict").read_bytes()
    ).items():
        variable = next(item for item in entry.values() if isinstance(item, dict))
        values[key] = variable["other"]
    return values


def pattern_read_keys(values: dict[str, str], root: Path = ROOT) -> set[str]:
    """Return the keys Swift builds from a prefix.

    A key fits a pattern and no literal names it, or it is `error.<code>` for a case of
    `ErrorCode`, which `error.\\(rawValue)` reads even where a literal names the same key. The
    `error.` pattern reads only codes, so another `error.` key is not in the family.
    """
    literals, patterns = keys.key_readers(root)
    codes = {
        f"error.{code}"
        for code in ERROR_CODE_CASE.findall(
            (root / ERROR_CODE_SOURCE).read_text(encoding="utf-8")
        )
    }
    return {
        key
        for key in values
        if key in codes
        or (
            key not in literals
            and any(
                pattern.fullmatch(key)
                for name, pattern in patterns.items()
                if not name.startswith("error.")
            )
        )
    }


def build(root: Path = ROOT) -> dict[str, object]:
    values = english_values(root)
    tree = command_tree(root)
    by_pattern = pattern_read_keys(values, root)
    mapping = {
        old: new_key(old, value, tree, old in by_pattern)
        for old, value in sorted(values.items())
    }
    by_value: dict[str, list[str]] = defaultdict(list)
    for old, value in values.items():
        by_value[value].append(old)
    duplicates = {
        value: sorted(olds) for value, olds in sorted(by_value.items()) if len(olds) > 1
    }
    neutral = sorted(old for old in by_pattern if keys.OS_WORDS.search(values[old]))
    return {
        "keys": mapping,
        "neutralTextRequired": neutral,
        "duplicateValues": duplicates,
    }


def render(root: Path = ROOT) -> str:
    text = json.dumps(build(root), indent="\t", ensure_ascii=False) + "\n"
    return format_json({MAP_PATH: text})[MAP_PATH]


def main() -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").split("\n\n")[0])
    parser.add_argument("--write", action="store_true")
    arguments = parser.parse_args()
    text = render()
    path = ROOT / MAP_PATH
    if arguments.write:
        path.write_text(text, encoding="utf-8")
        print(f"wrote {MAP_PATH}")
        return 0
    if not path.exists() or path.read_text(encoding="utf-8") != text:
        print(f"error: {MAP_PATH} is stale; run with --write", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
