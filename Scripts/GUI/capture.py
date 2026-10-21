"""Capture windows of the installed app into a git-ignored folder."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parents[2]
GUI_DIR = Path(__file__).resolve().parent
APP = Path("/Applications/OpenJoystickDriver.app")
PROCESS = "OpenJoystickDriver"
AREAS = ("Controllers", "Profiles", "Library", "Access", "Activity")
SETTINGS_PANES = ("General", "Notifications", "Advanced")
BOUNDS_TOLERANCE = 2.0


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
    return parser.parse_args(argv)


def run(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        detail = result.stderr.strip()
        if "assistive" in detail.lower() or "25211" in detail:
            raise CaptureError(
                "Accessibility permission is missing: allow the terminal in "
                "System Settings > Privacy & Security > Accessibility"
            )
        raise CaptureError(f"{' '.join(command[:3])} failed: {detail}")
    return result.stdout.strip()


def gui(script: str, *args: str) -> str:
    return run(["osascript", str(GUI_DIR / script), *args])


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


def window_id(pid: int, kind: str) -> int:
    reported = gui("window-bounds.applescript", kind)
    try:
        bounds = [float(value) for value in reported.split()]
    except ValueError as error:
        raise CaptureError(f"window-bounds reported {reported!r}") from error
    listing = run(
        ["osascript", "-l", "JavaScript", str(GUI_DIR / "window-list.js"), str(pid)]
    )
    for window in json.loads(listing):
        found = [window[key] for key in ("x", "y", "width", "height")]
        if all(abs(a - b) <= BOUNDS_TOLERANCE for a, b in zip(found, bounds)):
            return int(window["id"])
    raise CaptureError(f"no on-screen {kind} window has bounds {bounds}")


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


def capture(args: argparse.Namespace) -> int:
    pid = process_id()
    areas = AREAS if args.all else (args.area,) if args.area else ()
    panes = (
        SETTINGS_PANES
        if args.all
        else (args.settings_pane,)
        if args.settings_pane
        else ()
    )
    folder = make_folder()
    gui("open-main-window.applescript", str(APP))
    start_area = gui("current-sidebar.applescript")
    try:
        for area in areas:
            gui("select-sidebar.applescript", area)
            shoot(pid, "main", folder / f"main-{area.lower()}.png")
        for pane in panes:
            gui("open-settings.applescript", pane)
            shoot(pid, "settings", folder / f"settings-{pane.lower()}.png")
    finally:
        if panes:
            gui("close-settings.applescript")
        gui("select-sidebar.applescript", start_area)
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        return capture(args)
    except CaptureError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
