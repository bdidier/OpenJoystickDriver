from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from Scripts.Platform.swift_sdk import (
    FOUNDATION_MODULE,
    installed_sdks,
    interface_version,
    parse_version,
    select_sdk,
)


def make_sdk(root: Path, name: str, compiler: str) -> Path:
    sdk = root / name
    module = sdk / FOUNDATION_MODULE
    module.mkdir(parents=True)
    (module / "arm64e-apple-macos.swiftinterface").write_text(
        "// swift-interface-format-version: 1.0\n"
        f"// swift-compiler-version: Apple Swift version {compiler} effective-5.10\n"
        "import Swift\n",
        encoding="utf-8",
    )
    return sdk


class SwiftSDKTests(unittest.TestCase):
    def test_parses_apple_and_swift_org_versions(self) -> None:
        self.assertEqual(
            parse_version("Apple Swift version 6.4 (swiftlang-6.4.0.34.1)"), (6, 4)
        )
        self.assertEqual(
            parse_version("Apple Swift version 6.3.3 (swift-6.3.3-RELEASE)"), (6, 3)
        )
        self.assertIsNone(parse_version("no version here"))

    def test_reads_the_interface_compiler_version(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sdk = make_sdk(Path(directory), "MacOSX27.sdk", "6.4")
            self.assertEqual(interface_version(sdk), (6, 4))
            self.assertIsNone(interface_version(Path(directory) / "Missing.sdk"))

    def test_keeps_the_preferred_sdk_the_compiler_reads(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            older = make_sdk(root, "MacOSX26.sdk", "6.3.2")
            newer = make_sdk(root, "MacOSX27.sdk", "6.4")
            self.assertEqual(select_sdk((6, 4), newer, [older, newer]), newer)
            self.assertEqual(select_sdk((6, 3), older, [older, newer]), older)

    def test_older_compiler_gets_the_newest_sdk_it_reads(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            oldest = make_sdk(root, "MacOSX15.sdk", "6.1")
            older = make_sdk(root, "MacOSX26.sdk", "6.3.2")
            newer = make_sdk(root, "MacOSX27.sdk", "6.4")
            self.assertEqual(select_sdk((6, 3), newer, [oldest, older, newer]), older)

    def test_no_readable_sdk_selects_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            newer = make_sdk(Path(directory), "MacOSX27.sdk", "6.4")
            self.assertIsNone(select_sdk((6, 3), newer, [newer]))

    def test_installed_sdks_resolve_symlinks_once(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk = make_sdk(root, "MacOSX27.0.sdk", "6.4")
            (root / "MacOSX.sdk").symlink_to(sdk.name)
            self.assertEqual(installed_sdks([root]), [sdk.resolve()])


if __name__ == "__main__":
    unittest.main()
