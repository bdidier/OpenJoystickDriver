"""Command execution helpers."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

SCRIPT_DIR = Path(__file__).resolve().parents[1]
PROJECT_DIR = SCRIPT_DIR.parent
ENVIRONMENT = SCRIPT_DIR / "Platform/environment.sh"


def die(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def env_with(overrides: dict[str, str] | None = None) -> dict[str, str]:
    env = os.environ.copy()
    env.update(overrides or {})
    return env


def swift_command(args: list[str]) -> list[str]:
    """`swift <args>` run with the `swift` on PATH and the SDKROOT environment.sh selects for it."""
    return [
        "/bin/bash",
        "-c",
        'source "$1"; exec swift "${@:2}"',
        "ojd",
        str(ENVIRONMENT),
        *args,
    ]


def executed_test_count(output: str) -> int:
    """Tests a `swift test` run executed, counting XCTest and Swift Testing together.

    XCTest prints `Executed N tests` per suite and once more for the whole run, so its count is
    the largest; Swift Testing prints one `Test run with N tests` line.
    """
    xctest = [int(n) for n in re.findall(r"Executed (\d+) tests?\b", output)]
    testing = [int(n) for n in re.findall(r"Test run with (\d+) tests?\b", output)]
    return max(xctest, default=0) + max(testing, default=0)


def swift_test_package(directory: Path) -> int:
    """Runs `swift test` in `directory`; a run that executes no test at all fails."""
    completed = subprocess.run(
        swift_command(["test"]),
        cwd=directory,
        env=env_with(),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    output = completed.stdout or ""
    print(output, end="")
    if completed.returncode == 0 and executed_test_count(output) == 0:
        print(f"error: swift test in {directory} executed no tests", file=sys.stderr)
        return 1
    return completed.returncode


def run_record(args: list[str]) -> int:
    if not args:
        die("diagnose record requires a canonical controller JSON path")
    record = Path(args[0]).expanduser()
    if not record.is_absolute():
        record = Path.cwd() / record
    command = [
        "/bin/bash",
        "-c",
        'source "$1"; cd "$2"; exec swift run OpenJoystickDriverHIDTool --record-probe "$3" "${@:4}"',
        "ojd",
        str(ENVIRONMENT),
        str(PROJECT_DIR),
        str(record),
        *args[1:],
    ]
    return subprocess.run(command, env=env_with(), check=False).returncode


def run_usb_passive(args: list[str]) -> int:
    if len(args) != 2:
        die("diagnose usb-passive requires vid pid (hex, for example 0x3537 0x1010)")
    command = [
        "/bin/bash",
        "-c",
        'source "$1"; cd "$2"; exec swift run OpenJoystickDriverHIDTool --usb-passive --vid "$3" --pid "$4"',
        "ojd",
        str(ENVIRONMENT),
        str(PROJECT_DIR),
        *args,
    ]
    return subprocess.run(command, env=env_with(), check=False).returncode


def run_commands(commands: list[list[str]]) -> int:
    for command in commands:
        result = subprocess.run(command, cwd=PROJECT_DIR, env=env_with(), check=False)
        if result.returncode:
            return result.returncode
    return 0


HOOKS_PATH = ".husky/_"
HOOK_FILES = ("commit-msg", "pre-commit", "pre-push")


def install_hooks() -> int:
    """`bun install` runs the `prepare` script: husky, then pin-hooks-path.sh."""
    return run_commands([["bun", "install"]])


def main_checkout_dir() -> Path:
    """The checkout that owns the shared Git directory, also when run from a worktree."""
    result = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(result.stdout.strip()).parent


def validate_hooks() -> int:
    """Hooks must come from the main checkout, so every worktree runs them."""
    result = subprocess.run(
        ["git", "config", "--get", "core.hooksPath"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        check=False,
    )
    configured = result.stdout.strip()
    expected = main_checkout_dir() / HOOKS_PATH
    if configured != str(expected):
        print(
            f"error: core.hooksPath is {configured or 'unset'}, expected {expected}; "
            "run `./Scripts/ojd hooks install`",
            file=sys.stderr,
        )
        return 1
    if not expected.is_dir():
        print(
            f"error: {expected} does not exist; run `./Scripts/ojd hooks install`",
            file=sys.stderr,
        )
        return 1
    missing = [
        name for name in HOOK_FILES if not (PROJECT_DIR / ".husky" / name).is_file()
    ]
    if missing:
        print(
            f"error: missing hook files: {', '.join(f'.husky/{name}' for name in missing)}",
            file=sys.stderr,
        )
        return 1
    return 0
