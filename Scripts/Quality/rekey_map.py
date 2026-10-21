"""Build the old-to-new localization key map for the namespace re-key.

The map is one-off. It lives at `openspec/changes/platform-neutral-redesign/` while the re-key is
pending and goes away, with this script and its test, after the re-key lands. The re-key step reads
the map and renames each key in every `*.lproj` bundle without touching a value.

The strings keep changing until the tree is quiet, so regenerate right before the re-key:

    python3 -m Scripts.Quality.rekey_map --write

Without `--write` the script fails when the file differs from what the current en-US catalog and
the rules below produce. The rules:

- A key maps to the namespace of its screen or role (`AREA_PREFIXES`, `common`, `controller`,
  `keyboard`, `settings`, `cli`, `error`), and every segment becomes lowerCamelCase.
- A `cli` key becomes `cli.<group>.<command>.<leaf>`. A segment is a command when keys continue
  below it and no key ends at it; otherwise it is part of the leaf. A group's own text uses the
  command `group`. The cross-command groups `error`, `option`, `document` and `help` use the
  group `shared`.
- A value that names an operating system (`OS_WORDS`) moves under `platform.macos.`, with the
  namespaced key as the path. Splitting such a value into a neutral text and a platform text is
  a content change, not part of the re-key.
- Keys are not merged. `duplicate values` lists the English values shared by several keys, as
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
    "controller": ("term", "controllerModel"),
    "notifications": ("notify",),
    "a11y": ("a11y",),
    "status": ("status",),
    "mainMenu": ("ui", "menu", "main"),
    "menuBar": ("ui", "menu", "bar"),
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


def cli_key(parts: list[str], all_keys: list[list[str]]) -> list[str]:
    """Return the new segments of the `cli` key whose old segments, without `cli`, are `parts`."""
    group = parts[0]
    rest = parts[1:]
    if group in SHARED_CLI_GROUPS:
        return ["cli", "shared", group, join_leaf(rest)]
    if not rest:
        raise ValueError("cli key without a leaf")
    head = rest[0]
    below = [other for other in all_keys if other[:2] == [group, head]]
    is_command = len(rest) > 1 and all(len(other) > 2 for other in below)
    if is_command:
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


def new_segments(old: str, all_keys: list[list[str]]) -> list[str]:
    parts = old.split(".")
    top = parts[0]
    rest = parts[1:]
    if top == "cli":
        return cli_key(rest, [key[1:] for key in all_keys if key[0] == "cli"])
    if top in ("settings", "settingsPane"):
        return settings_key(parts)
    if top == "a11y" and rest[0] == "settingsPane":
        return ["a11y", "settings", "pane", join_leaf(rest[1:])]
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


def new_key(old: str, value: str, all_keys: list[list[str]]) -> str:
    key = new_segments(old, all_keys)
    if keys.OS_WORDS.search(value):
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


def build(root: Path = ROOT) -> dict[str, object]:
    values = english_values(root)
    all_keys = [key.split(".") for key in values]
    mapping = {
        old: new_key(old, value, all_keys) for old, value in sorted(values.items())
    }
    by_value: dict[str, list[str]] = defaultdict(list)
    for old, value in values.items():
        by_value[value].append(old)
    duplicates = {
        value: sorted(olds) for value, olds in sorted(by_value.items()) if len(olds) > 1
    }
    return {"keys": mapping, "duplicateValues": duplicates}


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
