from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from Scripts.Quality import check_neutral_core_imports as check

EXECUTABLE = "Sources/OpenJoystickDriver"
CLI = "Sources/OpenJoystickDriverCLI"


def write(root: Path, target: str, relative: str, text: str) -> None:
    path = root / target / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class NeutralCoreImportTests(unittest.TestCase):
    def test_neutral_targets_import_no_macos_only_module(self) -> None:
        self.assertEqual(check.violations(), [])

    def test_planted_import_in_the_executable_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, EXECUTABLE, "main.swift", "import Foundation\nimport AppKit\n")
            write(
                root, EXECUTABLE, "App/Host.swift", "@preconcurrency import IOKit.hid\n"
            )
            write(
                root,
                EXECUTABLE,
                "Other.swift",
                "#if canImport(SystemExtensions)\n#endif\n",
            )
            found = check.violations(root)
        self.assertEqual(
            found,
            [
                f"{EXECUTABLE}/App/Host.swift:1: IOKit",
                f"{EXECUTABLE}/Other.swift:1: SystemExtensions",
                f"{EXECUTABLE}/main.swift:2: AppKit",
            ],
        )

    def test_planted_import_in_the_cli_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(
                root,
                CLI,
                "Commands/Status/StatusCommand.swift",
                "import ArgumentParser\nimport OpenJoystickDriverService\n",
            )
            write(root, CLI, "Commands/Record.swift", "import OpenJoystickDriverUSB\n")
            write(root, CLI, "Root/UI.swift", "import SwiftUI\n")
            write(root, CLI, "Root/Host.swift", "import OpenJoystickDriverMacOSHost\n")
            found = check.violations(root)
        self.assertEqual(
            found,
            [
                f"{CLI}/Commands/Record.swift:1: OpenJoystickDriverUSB",
                f"{CLI}/Commands/Status/StatusCommand.swift:2: OpenJoystickDriverService",
                f"{CLI}/Root/Host.swift:1: OpenJoystickDriverMacOSHost",
                f"{CLI}/Root/UI.swift:1: SwiftUI",
            ],
        )

    def test_platform_directory_and_neutral_imports_are_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(
                root,
                EXECUTABLE,
                "platform/macos/Host.swift",
                "import AppKit\nimport IOKit\n",
            )
            write(
                root,
                EXECUTABLE,
                "main.swift",
                "import Foundation\nimport OpenJoystickDriverKit\n// import AppKit\n",
            )
            write(
                root,
                CLI,
                "CLI.swift",
                "import ArgumentParser\nimport Foundation\nimport OpenJoystickDriverKit\n",
            )
            self.assertEqual(check.violations(root), [])

    def test_the_host_adapter_target_is_not_scanned(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(
                root,
                "Sources/OpenJoystickDriverMacOSHost",
                "Host.swift",
                "import AppKit\nimport OpenJoystickDriverService\n",
            )
            self.assertEqual(check.violations(root), [])


if __name__ == "__main__":
    unittest.main()
