"""Compare the tree with, or rewrite, the equivalence snapshots in Tests/EquivalenceSnapshots."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

from ..Command.execution import swift_command

ROOT = Path(__file__).resolve().parents[2]
SNAPSHOTS = ROOT / "Tests" / "EquivalenceSnapshots"
TEST_FILTER = "EquivalenceSnapshot"


def parse_sections(text: str) -> dict[str, str]:
    """Split snapshot text into `## title` sections keyed by title."""
    sections: dict[str, list[str]] = {}
    title: str | None = None
    for line in text.splitlines():
        if line.startswith("## "):
            title = line[3:]
            sections[title] = []
        elif title is not None:
            sections[title].append(line)
    return {key: "\n".join(lines).strip("\n") for key, lines in sections.items()}


def diff_sections(expected: str, actual: str) -> list[str]:
    """Describe the records that were changed, added, or removed."""
    before = parse_sections(expected)
    after = parse_sections(actual)
    lines: list[str] = []
    for title in sorted(before.keys() | after.keys()):
        if title not in after:
            lines.append(f"  removed {title}")
        elif title not in before:
            lines.append(f"  added   {title}")
        elif before[title] != after[title]:
            lines.append(f"  changed {title}")
            old = before[title].splitlines()
            new = after[title].splitlines()
            for line in old:
                if line not in new:
                    lines.append(f"    - {line}")
            for line in new:
                if line not in old:
                    lines.append(f"    + {line}")
    return lines


def compare(snapshots: Path, actual: Path) -> dict[str, list[str]]:
    """Return the diff lines per snapshot file name; empty when nothing differs."""
    names = {path.name for path in snapshots.glob("*.txt")} | {
        path.name for path in actual.glob("*.txt")
    }
    result: dict[str, list[str]] = {}
    for name in sorted(names):
        recorded = snapshots / name
        current = actual / name
        if not current.is_file():
            result[name] = ["  no longer produced by the tree"]
            continue
        expected_text = recorded.read_text() if recorded.is_file() else ""
        difference = diff_sections(expected_text, current.read_text())
        if not recorded.is_file():
            difference = ["  snapshot file is missing", *difference]
        if difference:
            result[name] = difference
    return result


def run_tests(extra: dict[str, str]) -> int:
    environment = os.environ.copy()
    environment.update(extra)
    return subprocess.run(
        swift_command(["test", "--filter", TEST_FILTER]),
        cwd=ROOT,
        env=environment,
        check=False,
    ).returncode


def check() -> int:
    with tempfile.TemporaryDirectory(prefix="ojd-snapshots-") as directory:
        status = run_tests({"OJD_SNAPSHOT_ACTUAL_DIR": directory})
        if status != 0:
            print("error: the snapshot tests did not run", file=sys.stderr)
            return status
        differences = compare(SNAPSHOTS, Path(directory))
    if not differences:
        print("No differences from the equivalence snapshots.")
        return 0
    count = sum(
        1
        for lines in differences.values()
        for line in lines
        if not line.startswith("    ")
    )
    for name, lines in differences.items():
        print(f"{name}:")
        print("\n".join(lines))
    print(f"{count} difference(s). Run ./Scripts/ojd snapshots write to accept them.")
    return 1


def write() -> int:
    status = run_tests({"OJD_SNAPSHOT_WRITE": "1"})
    if status == 0:
        print(f"Rewrote the equivalence snapshots in {SNAPSHOTS.relative_to(ROOT)}.")
    return status


def main(argv: list[str] | None = None) -> int:
    arguments = sys.argv[1:] if argv is None else argv
    if arguments == ["check"]:
        return check()
    if arguments == ["write"]:
        return write()
    print("error: expected: check | write", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
