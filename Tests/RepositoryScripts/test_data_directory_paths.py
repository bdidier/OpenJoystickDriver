from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from Scripts.Quality import check_data_directory_paths as check


class DataDirectoryPathTests(unittest.TestCase):
    def test_sources_build_no_paths_outside_the_port(self) -> None:
        self.assertEqual(check.violations(), [])

    def test_violation_outside_the_port_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Sources/Example/Store.swift"
            source.parent.mkdir(parents=True)
            source.write_text(
                "let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)\n"
                "// NSHomeDirectory() in a comment is ignored\n",
                encoding="utf-8",
            )
            found = check.violations(root)
        self.assertEqual(len(found), 1)
        self.assertIn("Sources/Example/Store.swift:1", found[0])

    def test_port_file_is_exempt(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            port = (
                root / "Sources/OpenJoystickDriverKit/Storage/MacOSDataDirectory.swift"
            )
            port.parent.mkdir(parents=True)
            port.write_text('let path = "/tmp"\n', encoding="utf-8")
            self.assertEqual(check.violations(root), [])


if __name__ == "__main__":
    unittest.main()
