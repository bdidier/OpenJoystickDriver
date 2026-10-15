"""Fail when a neutral target imports a macOS-only module.

The neutral targets are the command-line grammar (`Sources/OpenJoystickDriverCLI`) and the
executable's own files (`Sources/OpenJoystickDriver`). They reach macOS only through the
`PlatformHost` protocol. Code that imports a macOS-only module lives in the host adapter target
(`Sources/OpenJoystickDriverMacOSHost`) or below a `platform` directory of the executable.
"""

from __future__ import annotations

import pathlib
import re
import sys
from collections.abc import Iterable

ROOT = pathlib.Path(__file__).resolve().parents[2]
NEUTRAL_TARGETS = (
    "Sources/OpenJoystickDriverCLI",
    "Sources/OpenJoystickDriver",
)
ADAPTER_DIRECTORY = "platform"
MACOS_ONLY_MODULES = frozenset(
    {
        "AppIntents",
        "AppKit",
        "AudioToolbox",
        "Cocoa",
        "CoreBluetooth",
        "CoreGraphics",
        "CoreHID",
        "DriverKit",
        "GameController",
        "IOBluetooth",
        "IOKit",
        "IOUSBHost",
        "OSLog",
        "OpenJoystickDriverMacOSHost",
        "OpenJoystickDriverPresentation",
        "OpenJoystickDriverService",
        "OpenJoystickDriverUSB",
        "Security",
        "ServiceManagement",
        "SwiftUI",
        "SwifterKit",
        "SystemExtensions",
        "USBDriverKit",
        "UserNotifications",
    }
)
IMPORT = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*import\s+(?:\w+\s+)?([A-Za-z_]\w*)")
CAN_IMPORT = re.compile(r"canImport\(\s*([A-Za-z_]\w*)\s*\)")


def modules_on(line: str) -> list[str]:
    """Return the modules a line imports or probes with `canImport`."""
    if line.lstrip().startswith("//"):
        return []
    found = [match.group(1) for match in CAN_IMPORT.finditer(line)]
    imported = IMPORT.match(line)
    if imported:
        found.append(imported.group(1))
    return found


def violations(root: pathlib.Path = ROOT) -> list[str]:
    found: list[str] = []
    for target in NEUTRAL_TARGETS:
        for path in sorted((root / target).rglob("*.swift")):
            relative = path.relative_to(root / target)
            if ADAPTER_DIRECTORY in relative.parts[:-1]:
                continue
            lines = path.read_text(encoding="utf-8").splitlines()
            for number, line in enumerate(lines, 1):
                for module in modules_on(line):
                    if module in MACOS_ONLY_MODULES:
                        found.append(
                            f"{target}/{relative.as_posix()}:{number}: {module}"
                        )
    return found


def main(arguments: Iterable[str] = ()) -> int:
    del arguments
    found = violations()
    for entry in found:
        print(f"macOS-only import in a neutral target: {entry}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
