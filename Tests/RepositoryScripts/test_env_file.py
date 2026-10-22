from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from Scripts.Platform import env_file

SCRIPT = Path(env_file.__file__)


class EnvFileTests(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def write(self, name: str, text: str) -> Path:
        path = self.root / name
        path.write_text(text, encoding="utf-8")
        return path

    def test_reads_quoted_values_and_expands_the_environment(self) -> None:
        path = self.write(
            ".env.dev",
            "# comment\n\n"
            'CODESIGN_IDENTITY="abc"\n'
            "DEVELOPMENT_TEAM=TEAM # trailing comment\n"
            'GUI_PROVISIONING_PROFILE="$HOME/Library/A B.provisionprofile"\n',
        )
        self.assertEqual(
            env_file.read(path, {"HOME": "/Users/me"}),
            {
                "CODESIGN_IDENTITY": "abc",
                "DEVELOPMENT_TEAM": "TEAM",
                "GUI_PROVISIONING_PROFILE": "/Users/me/Library/A B.provisionprofile",
            },
        )

    def test_a_missing_file_has_no_values(self) -> None:
        self.assertEqual(env_file.read(self.root / ".env.release", {}), {})

    def test_a_key_no_script_reads_stops_the_read(self) -> None:
        path = self.write(
            ".env.dev", 'CODESIGN_IDENTITY="a"\nDEXT_BUILD_IDENTITY="a"\n'
        )
        with self.assertRaisesRegex(
            env_file.EnvFileError, r":2: DEXT_BUILD_IDENTITY is not a key of \.env\.dev"
        ):
            env_file.read(path, {})

    def test_notarization_keys_belong_only_in_the_release_file(self) -> None:
        line = 'NOTARIZE_APPLE_ID="me@example.com"\n'
        with self.assertRaises(env_file.EnvFileError):
            env_file.read(self.write(".env.dev", line), {})
        self.assertEqual(
            env_file.read(self.write(".env.release", line), {}),
            {"NOTARIZE_APPLE_ID": "me@example.com"},
        )

    def test_a_line_without_an_assignment_stops_the_read(self) -> None:
        with self.assertRaisesRegex(env_file.EnvFileError, "expected KEY=value"):
            env_file.read(self.write(".env.dev", "CODESIGN_IDENTITY\n"), {})

    def test_update_replaces_one_key_and_keeps_the_other_lines(self) -> None:
        path = self.write(
            ".env.release", '# header\nNOTARIZE_APPLE_ID="old"\nDEVELOPMENT_TEAM="T"\n'
        )
        env_file.update(path, "NOTARIZE_APPLE_ID", "new")
        env_file.update(path, "NOTARIZE_KEYCHAIN_PROFILE", "OpenJoystickDriver")
        self.assertEqual(
            path.read_text(encoding="utf-8"),
            '# header\nNOTARIZE_APPLE_ID="new"\nDEVELOPMENT_TEAM="T"\n\n'
            'NOTARIZE_KEYCHAIN_PROFILE="OpenJoystickDriver"\n',
        )

    def test_the_read_command_prints_pairs_and_fails_on_an_unknown_key(self) -> None:
        good = self.write(".env.dev", 'DEVELOPMENT_TEAM="T"\n')
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "read", str(good)],
            capture_output=True,
            check=False,
        )
        self.assertEqual(
            (result.returncode, result.stdout), (0, b"DEVELOPMENT_TEAM\0T\0")
        )
        bad = self.write(".env.release", 'GUI_CODESIGN_IDENTITY="a"\n')
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "read", str(bad)],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn(
            "GUI_CODESIGN_IDENTITY is not a key of .env.release", result.stderr
        )


if __name__ == "__main__":
    unittest.main()
