from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class BiomePinTests(unittest.TestCase):
    def test_package_pin_matches_the_biome_schema_version(self) -> None:
        package = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))
        pin = package["devDependencies"]["@biomejs/biome"]
        self.assertRegex(pin, r"^\d+\.\d+\.\d+$", "the pin must be exact")
        config = json.loads((ROOT / "biome.json").read_text(encoding="utf-8"))
        match = re.fullmatch(
            r"https://biomejs\.dev/schemas/([^/]+)/schema\.json", config["$schema"]
        )
        self.assertIsNotNone(match, config["$schema"])
        assert match is not None
        self.assertEqual(pin, match.group(1))


if __name__ == "__main__":
    unittest.main()
