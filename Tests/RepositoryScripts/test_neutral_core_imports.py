from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from Scripts.Quality import check_neutral_core_imports as check

CORE = "Sources/OpenJoystickDriver"


def write(root: Path, relative: str, text: str) -> None:
    path = root / CORE / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class NeutralCoreImportTests(unittest.TestCase):
    def test_neutral_core_imports_no_macos_only_module(self) -> None:
        self.assertEqual(check.violations(), [])

    def test_planted_import_outside_platform_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "main.swift", "import Foundation\nimport AppKit\n")
            write(root, "App/Host.swift", "@preconcurrency import IOKit.hid\n")
            write(root, "Other.swift", "#if canImport(SystemExtensions)\n#endif\n")
            write(root, "Service.swift", "import OpenJoystickDriverService\n")
            found = check.violations(root)
        self.assertEqual(
            found,
            [
                f"{CORE}/App/Host.swift:1: IOKit",
                f"{CORE}/Other.swift:1: SystemExtensions",
                f"{CORE}/Service.swift:1: OpenJoystickDriverService",
                f"{CORE}/main.swift:2: AppKit",
            ],
        )

    def test_platform_directory_and_neutral_imports_are_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, "platform/macos/Host.swift", "import AppKit\nimport IOKit\n")
            write(
                root,
                "main.swift",
                "import Foundation\nimport OpenJoystickDriverKit\n// import AppKit\n",
            )
            self.assertEqual(check.violations(root), [])


if __name__ == "__main__":
    unittest.main()
