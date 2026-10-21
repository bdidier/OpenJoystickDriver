"""Capture windows of the installed app into a git-ignored folder."""

from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
import time
from collections.abc import Callable
from datetime import datetime
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parents[2]
GUI_DIR = Path(__file__).resolve().parent
APP = Path("/Applications/OpenJoystickDriver.app")
PROCESS = "OpenJoystickDriver"
BUNDLE_ID = "com.openjoystickdriver"
AREAS = ("Controllers", "Profiles", "Library", "Access", "Activity")
SETTINGS_PANES = ("General", "Notifications", "Advanced")
BOUNDS_TOLERANCE = 2.0
ACCESSIBILITY_GRANTED = "0"
ACCESSIBILITY_NOT_TRUSTED = "-25211"
ACCESSIBILITY_CANNOT_COMPLETE = "-25204"
# AXError -25204 is the app not answering Accessibility requests yet. No signal reports
# that the app answers: finished launching does not imply it, and an AXObserver needs an
# element that answers. Readiness is therefore polled, bounded by this deadline.
APP_READY_TIMEOUT_SECONDS = 15.0
APP_READY_POLL_SECONDS = 0.25


class CaptureError(Exception):
    pass


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="./Scripts/ojd shots capture",
        description="Capture app windows with screencapture -l into .ojd-shots/<timestamp>/.",
    )
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--area", choices=AREAS, help="sidebar area of the main window")
    choice.add_argument(
        "--settings-pane", choices=SETTINGS_PANES, help="tab of the Settings window"
    )
    choice.add_argument(
        "--all", action="store_true", help="every sidebar area and settings pane"
    )
    parser.add_argument(
        "--ready-timeout",
        type=float,
        default=APP_READY_TIMEOUT_SECONDS,
        metavar="SECONDS",
        help=(
            "longest wait for the app to answer Accessibility requests "
            f"(default {APP_READY_TIMEOUT_SECONDS:g})"
        ),
    )
    args = parser.parse_args(argv)
    if not math.isfinite(args.ready_timeout) or args.ready_timeout <= 0:
        parser.error(
            "--ready-timeout must be a finite number of seconds greater than zero"
        )
    return args


def run(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        detail = result.stderr.strip()
        if f"AXError {ACCESSIBILITY_NOT_TRUSTED}" in detail:
            raise CaptureError(not_trusted_message(ACCESSIBILITY_NOT_TRUSTED))
        raise CaptureError(f"{' '.join(command[:3])} failed: {detail}")
    return result.stdout.strip()


def ax(command: str, pid: int, *args: str) -> str:
    script = str(GUI_DIR / "ax.js")
    return run(["osascript", "-l", "JavaScript", script, command, str(pid), *args])


def gui(command: str, *args: str) -> str:
    return ax(command, process_id(), *args)


def session_state() -> str:
    script = str(GUI_DIR / "ax.js")
    return run(["osascript", "-l", "JavaScript", script, "session"])


def require_unlocked_console_session() -> None:
    """A locked or background session hides app windows from Accessibility and capture."""
    reported = session_state()
    found = re.fullmatch(r"locked=(true|false) console=(true|false)", reported)
    if not found:
        raise CaptureError(f"session state reported {reported!r}")
    if found.group(1) == "true":
        raise CaptureError(
            "the screen is locked: unlock this Mac's session and run the capture "
            "again; macOS hides app windows from Accessibility and screen capture "
            "while it is locked"
        )
    if found.group(2) == "false":
        raise CaptureError(
            "this login session is not on the console: switch to it and run the "
            "capture again; macOS hides app windows from Accessibility and screen "
            "capture in a session that is not on the console"
        )


def process_id() -> int:
    if not APP.is_dir():
        raise CaptureError(f"{APP} is not installed: ./Scripts/ojd build install dev")
    result = subprocess.run(
        ["pgrep", "-f", f"{APP}/Contents/MacOS/{PROCESS}$"],
        capture_output=True,
        text=True,
        check=False,
    )
    pids = result.stdout.split()
    if not pids:
        raise CaptureError(f"{PROCESS} is not running: open {APP}")
    return int(pids[0])


def not_trusted_message(code: str) -> str:
    return (
        f"Accessibility is not granted to the host app (AXError {code}): "
        "allow the host app in System Settings > Privacy & Security > "
        "Accessibility"
    )


def require_accessibility(
    pid: int,
    timeout: float = APP_READY_TIMEOUT_SECONDS,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> None:
    """Reads the app role through the Accessibility API and names each failure.

    AXError -25204 means the app does not answer yet, so only that code is waited on,
    until `timeout` seconds have passed on `clock`. Every other code fails at once.
    """
    deadline = clock() + timeout
    while True:
        code = ax("probe", pid)
        if code == ACCESSIBILITY_GRANTED:
            return
        if code == ACCESSIBILITY_NOT_TRUSTED:
            raise CaptureError(not_trusted_message(code))
        if code != ACCESSIBILITY_CANNOT_COMPLETE:
            raise CaptureError(
                f"Accessibility call to {PROCESS} failed (AXError {code}) although "
                "the host app is trusted: the app may not be responding, or the "
                "command is not running in a logged-in GUI session"
            )
        if clock() >= deadline:
            raise CaptureError(
                f"{PROCESS} did not answer Accessibility requests within "
                f"{timeout:g} s (last AXError {code}): wait for the app to "
                "finish launching and run the capture again, or raise "
                "--ready-timeout"
            )
        sleep(min(APP_READY_POLL_SECONDS, max(0.0, deadline - clock())))


def window_id(pid: int, kind: str) -> int:
    reported = gui("window-bounds", kind)
    try:
        bounds = [float(value) for value in reported.split()]
    except ValueError as error:
        raise CaptureError(f"window-bounds reported {reported!r}") from error
    if len(bounds) != 4:
        raise CaptureError(f"window-bounds reported {reported!r}, expected x y w h")
    listing = run(
        ["osascript", "-l", "JavaScript", str(GUI_DIR / "window-list.js"), str(pid)]
    )
    for window in json.loads(listing):
        found = [window[key] for key in ("x", "y", "width", "height")]
        if all(abs(a - b) <= BOUNDS_TOLERANCE for a, b in zip(found, bounds)):
            return int(window["id"])
    raise CaptureError(f"no on-screen {kind} window has bounds {bounds}")


def require_english_ui() -> None:
    """The GUI scripts click English labels, so another UI language is refused."""
    for domain in (BUNDLE_ID, "-g"):
        result = subprocess.run(
            ["defaults", "read", domain, "AppleLanguages"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            languages = re.findall(r"[A-Za-z]{2,3}(?:-[A-Za-z0-9]+)*", result.stdout)
            if languages and languages[0].lower().startswith("en"):
                return
            first = languages[0] if languages else "none"
            raise CaptureError(
                f"the app UI language is {first} ({domain}): the GUI scripts match "
                "English labels; put English first in System Settings > General > "
                "Language & Region"
            )
    raise CaptureError("AppleLanguages is unset: cannot tell the app UI language")


def read_state() -> tuple[bool, str | None]:
    """Whether the main window is open and which Settings tab is open, if any."""
    reported = gui("app-state")
    found = re.fullmatch(r"main=(true|false) settings=(\S+)", reported)
    if not found:
        raise CaptureError(f"app-state reported {reported!r}")
    tab = None if found.group(2) == "none" else found.group(2)
    if tab is not None and tab not in SETTINGS_PANES:
        raise CaptureError(f"the open Settings window shows unknown tab {tab!r}")
    return found.group(1) == "true", tab


def shoot(pid: int, kind: str, destination: Path) -> None:
    run(
        ["screencapture", "-x", "-l", str(window_id(pid, kind)), "-o", str(destination)]
    )
    if not destination.is_file() or destination.stat().st_size == 0:
        raise CaptureError(
            f"screencapture wrote no image to {destination}: grant Screen Recording"
        )
    print(destination)


def make_folder() -> Path:
    root = PROJECT_DIR / ".ojd-shots"
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    root.mkdir(exist_ok=True)
    for counter in range(1000):
        folder = root / (stamp if counter == 0 else f"{stamp}-{counter}")
        try:
            folder.mkdir()
        except FileExistsError:
            continue
        return folder
    raise CaptureError(f"no free capture folder for {stamp} in {root}")


def restore(steps: list[tuple[str, tuple[str, ...]]]) -> list[str]:
    """Runs every step, reports each failure to stderr and returns the failures."""
    failures = []
    for label, command in steps:
        try:
            gui(*command)
        except (CaptureError, OSError) as error:
            failures.append(label)
            print(f"error: restore {label}: {error}", file=sys.stderr)
    return failures


def capture(args: argparse.Namespace) -> int:
    pid = process_id()
    require_unlocked_console_session()
    require_accessibility(pid, args.ready_timeout)
    require_english_ui()
    areas = AREAS if args.all else (args.area,) if args.area else ()
    panes = (
        SETTINGS_PANES
        if args.all
        else (args.settings_pane,)
        if args.settings_pane
        else ()
    )
    main_was_open, settings_tab = read_state()
    folder = make_folder()
    sidebar = None
    opens_settings = False
    try:
        run(["open", str(APP)])
        gui("wait-main-window")
        sidebar = gui("current-sidebar")
        for area in areas:
            gui("select-sidebar", area)
            shoot(pid, "main", folder / f"main-{area.lower()}.png")
        for pane in panes:
            opens_settings = settings_tab is None
            gui("open-settings", pane)
            shoot(pid, "settings", folder / f"settings-{pane.lower()}.png")
    finally:
        steps: list[tuple[str, tuple[str, ...]]] = []
        if sidebar is not None:
            steps.append(("sidebar area", ("select-sidebar", sidebar)))
        if settings_tab is not None and panes:
            steps.append(("settings tab", ("open-settings", settings_tab)))
        if opens_settings:
            steps.append(("settings window", ("close-window", "settings")))
        if not main_was_open:
            steps.append(("main window", ("close-window", "main")))
        failures = restore(steps)
    return 2 if failures else 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        return capture(args)
    except CaptureError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
