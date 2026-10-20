from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

from Scripts.Catalog import validate_profiles
from Scripts.Catalog.schema_header import header
from Scripts.Quality import validate_schemas

BUTTON = {"kind": "Button", "page": 9, "usage": 1, "control": "South"}
AXIS = {"kind": "Axis", "page": 1, "usage": 48, "control": "LeftStickX"}
HAT = {"kind": "Hat", "page": 1, "usage": 57}


def record(input_section: Any, family: str = "HIDDescriptor") -> dict[str, Any]:
    document: dict[str, Any] = {
        **header("Controller"),
        "vendorID": 0xFFFE,
        "productID": 1,
        "modes": [{"id": "default", "protocol": {"family": family}}],
    }
    if input_section is not None:
        document["input"] = input_section
    return document


def usage_map(*usages: dict[str, Any], **members: Any) -> dict[str, Any]:
    return {"hidUsageMap": {"usages": list(usages), **members}}


class HIDUsageMapRecordSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = validate_profiles.validator()

    def test_accepts_each_usage_kind(self) -> None:
        accepted = {
            "button": usage_map(BUTTON),
            "stick axis": usage_map(AXIS),
            "axis range, inversion and dead zone": usage_map(
                {
                    **AXIS,
                    "inverted": True,
                    "range": {"min": -128, "max": 127},
                    "deadZone": 0.1,
                }
            ),
            "trigger axis": usage_map(
                {**AXIS, "usage": 50, "control": "RightTrigger", "deadZone": 0.05}
            ),
            "digital trigger button": usage_map({**BUTTON, "control": "LeftTrigger"}),
            "hat": usage_map(HAT),
            "hat starting at 0": usage_map({**HAT, "range": {"min": 0, "max": 7}}),
            "hat starting at 1": usage_map({**HAT, "range": {"min": 1, "max": 8}}),
            "report id": usage_map(BUTTON, reportID=6),
            "no input": None,
        }
        for name, input_section in accepted.items():
            with self.subTest(name):
                self.assertTrue(self.validator.is_valid(record(input_section)))

    def test_rejects_invalid_usages(self) -> None:
        rejected = {
            "empty usages": usage_map(),
            "button on a stick": usage_map({**BUTTON, "control": "LeftStickX"}),
            "button on the dpad": usage_map({**BUTTON, "control": "DpadUp"}),
            "axis on a button": usage_map({**AXIS, "control": "South"}),
            "axis on the dpad": usage_map({**AXIS, "control": "DpadUp"}),
            "hat on a button": usage_map({**HAT, "control": "South"}),
            "hat range 2...9": usage_map({**HAT, "range": {"min": 2, "max": 9}}),
            "hat with a dead zone": usage_map({**HAT, "deadZone": 0.1}),
            "button with a dead zone": usage_map({**BUTTON, "deadZone": 0.1}),
            "dead zone 0": usage_map({**AXIS, "deadZone": 0}),
            "dead zone 1": usage_map({**AXIS, "deadZone": 1}),
            "negative dead zone": usage_map({**AXIS, "deadZone": -0.1}),
            "range without max": usage_map({**AXIS, "range": {"min": 0}}),
            "range beyond 32 bits": usage_map(
                {**AXIS, "range": {"min": 0, "max": 2**31}}
            ),
            "unknown kind": usage_map({**AXIS, "kind": "slider"}),
            "unknown field": usage_map({**BUTTON, "extra": 1}),
            "page 0": usage_map({**BUTTON, "page": 0}),
            "usage 65536": usage_map({**BUTTON, "usage": 65536}),
            "report id 0": usage_map(BUTTON, reportID=0),
            "report id 256": usage_map(BUTTON, reportID=256),
            "descriptor shapes in a record": {
                "descriptorShapes": [
                    {
                        "present": [{"page": 1, "usage": 50}],
                        "hidUsageMap": usage_map(BUTTON)["hidUsageMap"],
                    }
                ]
            },
        }
        for name, input_section in rejected.items():
            with self.subTest(name):
                self.assertFalse(self.validator.is_valid(record(input_section)))

    def test_a_usage_map_belongs_to_hid_descriptor_only(self) -> None:
        self.assertFalse(
            self.validator.is_valid(record(usage_map(BUTTON), "SonyDualShock4"))
        )

    def test_a_byte_layout_belongs_to_report_layout_only(self) -> None:
        layout = {
            "report": {"length": 1},
            "buttons": [{"control": "South", "byte": 0, "mask": 1}],
        }
        self.assertTrue(self.validator.is_valid(record(layout, "HIDReportLayout")))
        self.assertFalse(self.validator.is_valid(record(layout)))
        self.assertFalse(
            self.validator.is_valid(record(usage_map(BUTTON), "HIDReportLayout"))
        )

    def validate_file(self, input_section: Any) -> None:
        with tempfile.TemporaryDirectory(prefix="ojd-hid-record-") as directory:
            path = Path(directory) / "record.json"
            path.write_text(json.dumps(record(input_section)), encoding="utf-8")
            validate_profiles.validate_record(
                path, enforce_path=False, schema_validator=self.validator
            )

    def test_validator_rejects_what_the_schema_cannot_express(self) -> None:
        duplicate = usage_map(AXIS, {**AXIS, "control": "LeftStickY"})
        flat = usage_map({**AXIS, "range": {"min": 5, "max": 5}})
        backwards = usage_map({**AXIS, "range": {"min": 9, "max": 3}})
        for name, input_section in {
            "duplicate usage": duplicate,
            "empty axis range": flat,
            "reversed axis range": backwards,
        }.items():
            with self.subTest(name):
                self.assertTrue(self.validator.is_valid(record(input_section)))
                with self.assertRaises(validate_profiles.ValidationError):
                    self.validate_file(input_section)
        self.validate_file(usage_map(AXIS, BUTTON))

    def test_hid_descriptor_declares_no_parameters(self) -> None:
        document = record(None)
        document["modes"][0]["protocol"]["parameters"] = {"usageLayout": "Wr007"}
        self.assertFalse(self.validator.is_valid(document))


class HIDUsageMapDescriptionSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.documents = validate_schemas.validate_schema_documents()
        self.registry = validate_schemas.schema_registry(self.documents)
        self.schema: Any = self.documents["protocol-description.schema.json"]
        directory = tempfile.TemporaryDirectory(prefix="ojd-hid-usage-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        patcher = mock.patch.object(validate_schemas, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)

    def check(self, defaults: dict[str, Any], **members: Any) -> None:
        document = {
            **header("ProtocolDescription"),
            "family": "HIDDescriptor",
            "endpoints": {"in": 130, "out": 2},
            "tuningKeys": ["hidStartupIntervalMs", "minimumHIDOutputIntervalMs"],
            "defaults": defaults,
            **members,
        }
        path = self.root / "hid-descriptor.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        validate_schemas.validate_protocol_descriptions(
            self.schema, self.registry, [path]
        )

    def assert_rejected(self, defaults: dict[str, Any], **members: Any) -> None:
        with self.assertRaisesRegex(validate_schemas.ValidationError, r"^E5002: "):
            self.check(defaults, **members)

    def shape(self, **members: Any) -> dict[str, Any]:
        return {
            "present": [{"page": 1, "usage": 50}],
            "hidUsageMap": usage_map(BUTTON)["hidUsageMap"],
            **members,
        }

    def test_accepts_a_standard_map_and_descriptor_shapes(self) -> None:
        self.check({"input": usage_map(BUTTON, AXIS, HAT)})
        self.check(
            {
                "input": {
                    **usage_map(BUTTON),
                    "descriptorShapes": [
                        self.shape(
                            absent=[{"page": 1, "usage": 51}],
                            anyOf=[{"page": 2, "usage": 197}],
                        )
                    ],
                }
            }
        )

    def test_rejects_invalid_shapes_and_maps(self) -> None:
        self.assert_rejected({"input": {"descriptorShapes": []}})
        self.assert_rejected({"input": {"descriptorShapes": [{"present": []}]}})
        self.assert_rejected({"input": {"descriptorShapes": [self.shape(present=[])]}})
        self.assert_rejected({"input": {"descriptorShapes": [self.shape(extra=True)]}})
        self.assert_rejected({"input": usage_map({**BUTTON, "control": "DpadUp"})})
        self.assert_rejected({"input": usage_map()})

    def test_rejects_duplicate_usages_and_empty_ranges(self) -> None:
        duplicate = usage_map(AXIS, {**AXIS, "control": "LeftStickY"})
        backwards = usage_map({**AXIS, "range": {"min": 9, "max": 3}})
        self.assert_rejected({"input": duplicate})
        self.assert_rejected({"input": backwards})
        self.assert_rejected(
            {
                "input": {
                    "descriptorShapes": [
                        self.shape(hidUsageMap=duplicate["hidUsageMap"])
                    ]
                }
            }
        )
        self.assert_rejected(
            {
                "input": {
                    "descriptorShapes": [
                        self.shape(hidUsageMap=backwards["hidUsageMap"])
                    ]
                }
            }
        )

    def test_rejects_usage_maps_in_other_families(self) -> None:
        document = {
            **header("ProtocolDescription"),
            "family": "SonyDualSense",
            "defaults": {"input": usage_map(BUTTON)},
        }
        path = self.root / "sony-dualsense.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        with self.assertRaisesRegex(validate_schemas.ValidationError, r"^E5002: "):
            validate_schemas.validate_protocol_descriptions(
                self.schema, self.registry, [path]
            )


if __name__ == "__main__":
    unittest.main()
