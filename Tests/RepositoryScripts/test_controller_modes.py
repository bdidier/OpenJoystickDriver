from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any

from Scripts.Catalog import validate_profiles
from Scripts.Catalog.schema_header import header

SIXAXIS = {"family": "sony.sixaxis"}
ANSWERS = {"report": 239, "length": 64, "expect": "answers"}


def mode(identifier: str, *probes: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": identifier,
        "protocol": SIXAXIS,
        "match": {"probes": list(probes or [ANSWERS])},
    }


def record(**fields: Any) -> dict[str, Any]:
    return {
        **header("Controller"),
        "vendorID": 0x054C,
        "productID": 0x0268,
        "protocol": SIXAXIS,
        **fields,
    }


class ControllerModeSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = validate_profiles.validator()

    def test_accepts_modes_selected_by_each_probe_expectation(self) -> None:
        document = record(
            modes=[
                mode("answers", ANSWERS),
                mode("stalls", {"report": 239, "length": 64, "expect": "stalls"}),
                mode(
                    "pattern",
                    {
                        "report": 1,
                        "length": 64,
                        "expect": "bytes",
                        "offset": 2,
                        "bytes": "03 04",
                    },
                ),
            ]
        )
        self.assertTrue(self.validator.is_valid(document))

    def test_rejects_invalid_modes(self) -> None:
        bytes_probe = {"report": 1, "length": 8, "expect": "bytes"}
        rejected = {
            "empty modes": record(modes=[]),
            "default is reserved": record(modes=[mode("default")]),
            "uppercase id": record(modes=[mode("XInput")]),
            "no probes": record(
                modes=[{"id": "x", "protocol": SIXAXIS, "match": {"probes": []}}]
            ),
            "no match": record(modes=[{"id": "x", "protocol": SIXAXIS}]),
            "unknown match key": record(
                modes=[
                    {
                        "id": "x",
                        "protocol": SIXAXIS,
                        "match": {"probes": [ANSWERS], "bcdDevice": 1},
                    }
                ]
            ),
            "write probe": record(modes=[mode("x", {**ANSWERS, "write": "01"})]),
            "unknown expectation": record(
                modes=[mode("x", {**ANSWERS, "expect": "a"})]
            ),
            "bytes without pattern": record(modes=[mode("x", bytes_probe)]),
            "pattern on answers": record(
                modes=[mode("x", {**ANSWERS, "offset": 0, "bytes": "01"})]
            ),
            "lowercase hex": record(
                modes=[mode("x", {**bytes_probe, "offset": 0, "bytes": "ab"})]
            ),
            "unpaired hex": record(
                modes=[mode("x", {**bytes_probe, "offset": 0, "bytes": "A"})]
            ),
            "report above 255": record(modes=[mode("x", {**ANSWERS, "report": 256})]),
        }
        for name, document in rejected.items():
            with self.subTest(name):
                self.assertFalse(self.validator.is_valid(document))

    def test_validator_rejects_duplicate_ids_and_overflowing_bytes(self) -> None:
        overflowing = {
            "report": 1,
            "length": 3,
            "expect": "bytes",
            "offset": 2,
            "bytes": "03 04",
        }
        rejected = {
            "duplicate id": record(modes=[mode("a"), mode("a")]),
            "bytes past length": record(modes=[mode("a", overflowing)]),
        }
        for name, document in rejected.items():
            with self.subTest(name), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "record.json"
                path.write_text(json.dumps(document))
                with self.assertRaises(validate_profiles.ValidationError):
                    validate_profiles.validate_record(path, enforce_path=False)


if __name__ == "__main__":
    unittest.main()
