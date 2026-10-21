from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "Sources/OpenJoystickDriverKit/Resources"
ENGLISH_ONLY = {"C.lproj", "en-US.lproj"}


class CrowdinConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = (ROOT / "crowdin.yml").read_text(encoding="utf-8")

    def sources(self) -> list[str]:
        return re.findall(r"^\s*- source: (\S+)$", self.text, re.MULTILINE)

    def test_both_source_patterns_are_present(self) -> None:
        base = "/Sources/OpenJoystickDriverKit/Resources/en-US.lproj"
        self.assertEqual(self.sources(), [f"{base}/*.strings", f"{base}/*.stringsdict"])

    def test_every_source_has_the_translation_path(self) -> None:
        paths = re.findall(r"^\s+translation: (\S+)$", self.text, re.MULTILINE)
        self.assertEqual(
            paths,
            [
                "/Sources/OpenJoystickDriverKit/Resources/%osx_locale%.lproj/%original_file_name%"
            ]
            * 2,
        )

    def test_language_mapping_names_every_shipped_locale_once(self) -> None:
        shipped = sorted(
            path.name.removesuffix(".lproj")
            for path in RESOURCES.glob("*.lproj")
            if path.name not in ENGLISH_ONLY
        )
        blocks = re.split(r"^\s+languages_mapping:\n", self.text, flags=re.MULTILINE)[
            1:
        ]
        self.assertEqual(len(blocks), 2)
        for block in blocks:
            mapped = re.findall(r"^\s{8}[A-Za-z-]+: (\S+)$", block, re.MULTILINE)
            self.assertEqual(sorted(mapped), shipped)
        self.assertEqual(len(shipped), 20)

    def test_credentials_come_from_the_environment(self) -> None:
        self.assertIn("project_id_env: CROWDIN_PROJECT_ID", self.text)
        self.assertIn("api_token_env: CROWDIN_PERSONAL_TOKEN", self.text)
        self.assertNotRegex(self.text, r"(?m)^(?:api_token|project_id):")


class BundleContentTests(unittest.TestCase):
    def test_no_template_catalog_is_in_the_resource_tree(self) -> None:
        """The Kit target processes `Resources/`, so nothing named like a template ships."""
        self.assertEqual(sorted(RESOURCES.rglob("Localizable.template.*")), [])
        self.assertFalse((RESOURCES / "Localization").exists())


if __name__ == "__main__":
    unittest.main()
