"""The shared `ControllerPatch` cases; `ControllerPatchMergeTests.swift` reads the same file."""

from __future__ import annotations

import json
import unittest
from pathlib import Path
from typing import Any

from Scripts.Catalog import controller_patch

CASES = Path(__file__).resolve().parent / "fixtures" / "controller_patch" / "cases.json"


def load_cases() -> dict[str, Any]:
    return json.loads(CASES.read_text(encoding="utf-8"))


class ControllerPatchTests(unittest.TestCase):
    def test_every_case_gives_its_effective_record(self) -> None:
        cases = load_cases()["cases"]
        self.assertGreaterEqual(len(cases), 10)
        for case in cases:
            with self.subTest(case=case["name"]):
                layers = {name: case[name] for name in controller_patch.LAYERS}
                self.assertEqual(
                    controller_patch.effective_record(case["record"], layers),
                    case["expected"],
                )

    def test_rejected_documents_are_refused(self) -> None:
        for case in load_cases()["rejected"]:
            with (
                self.subTest(case=case["name"]),
                self.assertRaises(controller_patch.PatchError),
            ):
                controller_patch.parse_patch(case["document"])

    def test_the_cases_cover_the_required_behaviour(self) -> None:
        names = {case["name"] for case in load_cases()["cases"]}
        self.assertIn("null deletes a parameter", names)
        self.assertIn("a user patch beats a package patch", names)

    def test_a_case_record_is_not_changed(self) -> None:
        case = load_cases()["cases"][0]
        before = json.dumps(case["record"], sort_keys=True)
        controller_patch.effective_record(
            case["record"], {name: case[name] for name in controller_patch.LAYERS}
        )
        self.assertEqual(json.dumps(case["record"], sort_keys=True), before)


if __name__ == "__main__":
    unittest.main()
