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
            "id with a trailing newline": record(modes=[mode("abc\n")]),
            "bytes with a trailing newline": record(
                modes=[mode("x", {**bytes_probe, "offset": 0, "bytes": "AB\n"})]
            ),
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

    def test_validator_rejects_modes_that_break_record_level_rules(self) -> None:
        layout = {
            "report": {"length": 8},
            "buttons": [{"control": "South", "byte": 0, "mask": 1}],
        }
        rumble = {
            "rumble": {
                "report": {"kind": "output", "id": 2, "length": 8},
                "leftMain": {"byte": 3},
            }
        }

        def with_mode(family: str, default: str, **fields: Any) -> dict[str, Any]:
            return {
                **record(**fields),
                "protocol": {"family": default},
                "modes": [
                    {
                        "id": "x",
                        "protocol": {"family": family},
                        "match": {"probes": [ANSWERS]},
                    }
                ],
            }

        needs_layout = "every mode needs the record's input layout exactly when it is hid.report-layout"
        rejected = {
            "raw-USB mode": (
                with_mode("xbox.gip", "sony.sixaxis"),
                "modes apply only to HID controllers",
            ),
            "raw-USB default": (
                with_mode("sony.sixaxis", "xbox.gip"),
                "modes apply only to HID controllers",
            ),
            "input layout on a mode that is not hid.report-layout": (
                with_mode("sony.sixaxis", "hid.report-layout", input=layout),
                needs_layout,
            ),
            "hid.report-layout mode without the input layout": (
                with_mode("hid.report-layout", "sony.sixaxis"),
                needs_layout,
            ),
            "rumble template on a mode whose driver does not encode it": (
                with_mode("hid.descriptor", "vendor.ps3-third-party", output=rumble),
                "rumble templates require a driver that encodes them in every mode",
            ),
            "present controls on a mode whose driver does not declare them": (
                with_mode(
                    "sony.sixaxis",
                    "sony.dualsense",
                    capabilities={
                        "present": sorted(validate_profiles.DUALSENSE_EDGE_CONTROLS)
                    },
                ),
                "capabilities must be deltas the driver of every mode declares",
            ),
        }
        for name, (document, message) in rejected.items():
            with self.subTest(name), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "record.json"
                path.write_text(json.dumps(document))
                with self.assertRaises(validate_profiles.ValidationError) as caught:
                    validate_profiles.validate_record(path, enforce_path=False)
                self.assertIn(message, str(caught.exception))


if __name__ == "__main__":
    unittest.main()
