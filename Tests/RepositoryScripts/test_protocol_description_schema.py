from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from Scripts.Catalog.schema_header import header
from Scripts.Quality import validate_schemas

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def xusb_description() -> dict[str, Any]:
    return {
        **header("ProtocolDescription"),
        "family": "xbox.xusb",
        "interfaceSignatures": [
            {
                "variant": "wired",
                "interfaceClass": 255,
                "interfaceSubclass": 93,
                "interfaceProtocol": 1,
            }
        ],
    }


class ProtocolDescriptionSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.documents = validate_schemas.validate_schema_documents()
        self.registry = validate_schemas.schema_registry(self.documents)
        self.schema: Any = self.documents["protocol-description.schema.json"]
        directory = tempfile.TemporaryDirectory(prefix="ojd-protocols-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        root_patch = patch.object(validate_schemas, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)

    def check(self, document: dict[str, Any], name: str | None = None) -> None:
        path = self.root / (name or f"{document.get('family')}.json")
        path.write_text(json.dumps(document), encoding="utf-8")
        validate_schemas.validate_protocol_descriptions(
            self.schema, self.registry, [path]
        )

    def assert_rejected(
        self,
        document: dict[str, Any],
        name: str | None = None,
        code: str = "E5002",
    ) -> None:
        with self.assertRaisesRegex(validate_schemas.ValidationError, rf"^{code}: "):
            self.check(document, name)

    def test_authored_descriptions_validate(self) -> None:
        paths = sorted(validate_schemas.PROTOCOL_DESCRIPTIONS.glob("*.json"))
        self.assertEqual(
            [path.stem for path in paths],
            [
                "hid.descriptor",
                "nintendo.switch1",
                "nintendo.switch2",
                "sony.dualsense",
                "sony.dualshock4",
                "vendor.gamesir",
                "vendor.nvidia-shield",
                "vendor.ps3-third-party",
                "xbox.gip",
                "xbox.xid",
                "xbox.xusb",
            ],
        )
        with patch.object(validate_schemas, "ROOT", REPOSITORY_ROOT):
            validate_schemas.validate_protocol_descriptions(
                self.schema, self.registry, paths
            )

    def test_accepts_a_minimal_description(self) -> None:
        self.check(xusb_description())

    def test_rejects_a_missing_or_foreign_header(self) -> None:
        for member, value in (
            ("apiVersion", None),
            ("apiVersion", "openjoystickdriver.io/v1beta1"),
            ("kind", None),
            ("kind", "Controller"),
        ):
            with self.subTest(member=member, value=value):
                document = xusb_description()
                if value is None:
                    del document[member]
                else:
                    document[member] = value
                code = "E5001" if member == "apiVersion" else "E5002"
                self.assert_rejected(document, code=code)

    def test_rejects_an_unknown_family(self) -> None:
        document = xusb_description()
        document["family"] = "xbox.unknown"
        self.assert_rejected(document)

    def test_rejects_a_byte_out_of_range(self) -> None:
        for field, value in (
            ("interfaceClass", 256),
            ("interfaceSubclass", -1),
            ("interfaceProtocol", 1.5),
            ("interfaceNumber", 300),
        ):
            with self.subTest(field=field):
                document = xusb_description()
                document["interfaceSignatures"][0][field] = value
                self.assert_rejected(document)

    def test_rejects_empty_signatures_and_admits_none(self) -> None:
        empty = xusb_description()
        empty["interfaceSignatures"] = []
        self.assert_rejected(empty)
        # A description may carry only parameters or defaults.
        absent = xusb_description()
        del absent["interfaceSignatures"]
        absent["parameters"] = {}
        self.assert_rejected(absent)
        del absent["parameters"]
        self.check(absent)

    def test_rejects_a_signature_missing_a_triple_field(self) -> None:
        for field in ("variant", "interfaceClass", "interfaceSubclass"):
            with self.subTest(field=field):
                document = xusb_description()
                del document["interfaceSignatures"][0][field]
                self.assert_rejected(document)

    def test_rejects_unknown_fields(self) -> None:
        top = xusb_description()
        top["vendorID"] = 1118
        self.assert_rejected(top)
        nested = xusb_description()
        nested["interfaceSignatures"][0]["endpoint"] = 129
        self.assert_rejected(nested)

    def test_rejects_a_duplicate_signature(self) -> None:
        document = xusb_description()
        signatures = document["interfaceSignatures"]
        signatures.append(copy.deepcopy(signatures[0]))
        self.assert_rejected(document)

    def family_variants(self) -> dict[str, list[str]]:
        """Each family's admitted variants; the Swift tests keep these equal to `variants`."""
        families: dict[str, list[str]] = {}
        for rule in self.schema["allOf"]:
            family = rule["if"]["properties"]["family"]["const"]
            signatures = rule["then"]["properties"]["interfaceSignatures"]
            families[family] = (
                signatures["items"]["properties"]["variant"]["enum"]
                if signatures is not False
                else []
            )
        return families

    def described(self, family: str, variant: str) -> dict[str, Any]:
        document = xusb_description()
        document["family"] = family
        document["interfaceSignatures"][0]["variant"] = variant
        return document

    def test_every_family_has_a_variant_rule(self) -> None:
        families = self.family_variants()
        controller: Any = self.documents["controller.schema.json"]
        self.assertEqual(
            sorted(families),
            sorted(controller["$defs"]["protocol"]["properties"]["family"]["enum"]),
        )
        self.assertEqual(families["sony.dualshock4"], ["usb", "bluetooth-classic"])
        self.assertEqual(families["hid.descriptor"], [])

    def test_each_family_accepts_only_its_own_variants(self) -> None:
        every = self.schema["$defs"]["interfaceSignature"]["properties"]["variant"][
            "enum"
        ]
        for family, allowed in self.family_variants().items():
            for variant in every:
                with self.subTest(family=family, variant=variant):
                    document = self.described(family, variant)
                    if variant in allowed:
                        self.check(document)
                    else:
                        self.assert_rejected(document, code="E5004")

    def test_rejects_a_file_name_that_differs_from_the_family(self) -> None:
        with self.assertRaisesRegex(
            validate_schemas.ValidationError,
            r"^E5003: .*file name must be xbox\.xusb\.json",
        ):
            self.check(xusb_description(), name="xbox.gip.json")

    # Parameters and defaults.

    def with_body(self, family: str, **members: Any) -> dict[str, Any]:
        return {**header("ProtocolDescription"), "family": family, **members}

    def test_accepts_parameters_and_defaults(self) -> None:
        self.check(
            self.with_body(
                "sony.dualsense",
                parameters={
                    "maker": {"type": "enum", "values": ["ThirdParty"]},
                    "forcedVibration": {"type": "flag"},
                },
                defaults={"tuning": {"stickDeadzone": 0.1}},
            )
        )
        self.check(
            self.with_body(
                "xbox.gip",
                parameters={
                    "shareButton": {
                        "type": "object",
                        "fields": {
                            "fromEnd": {
                                "type": "integer",
                                "minimum": 1,
                                "maximum": 255,
                            }
                        },
                    }
                },
            )
        )
        self.check(
            self.with_body(
                "hid.report-layout",
                defaults={
                    "input": {
                        "report": {"length": 1},
                        "buttons": [{"control": "face-south", "byte": 0, "mask": 1}],
                    }
                },
            )
        )
        self.check(
            self.with_body(
                "xbox.xid",
                defaults={
                    "input": {
                        "report": {"length": 4},
                        "axes": [
                            {
                                "control": "left-stick-x",
                                "byte": 0,
                                "bits": 16,
                                "signed": True,
                                "min": -32768,
                                "max": 32767,
                                "symmetric": True,
                            }
                        ],
                        "hat": [
                            {
                                "encoding": "table",
                                "byte": 2,
                                "mask": 15,
                                "values": {"1": "north", "9": "northEast"},
                            }
                        ],
                    }
                },
            )
        )

    def test_rejects_a_bad_parameter_declaration(self) -> None:
        for declaration in (
            {"type": "string"},
            {"type": "flag", "values": ["A"]},
            {"type": "enum"},
            {"type": "enum", "values": []},
            {"type": "enum", "values": ["lower"]},
            {"type": "enum", "values": ["A", "A"]},
            {"type": "object", "fields": {}},
            {"type": "object", "fields": {"x": {"type": "integer", "minimum": 1}}},
            {"type": "object", "fields": {"x": {"type": "string"}}},
        ):
            with self.subTest(declaration=declaration):
                self.assert_rejected(
                    self.with_body("sony.dualsense", parameters={"maker": declaration})
                )

    def test_rejects_a_parameter_the_family_does_not_declare(self) -> None:
        flag = {"type": "flag"}
        self.assert_rejected(self.with_body("sony.dualsense", parameters={"x": flag}))
        self.assert_rejected(
            self.with_body("sony.dualsense", parameters={"layout": flag})
        )
        self.assert_rejected(self.with_body("xbox.xid", parameters={"layout": flag}))
        self.assert_rejected(self.with_body("sony.dualsense", parameters={}))

    def test_rejects_defaults_a_driver_does_not_read(self) -> None:
        input_layout = {
            "report": {"length": 1},
            "buttons": [{"control": "face-south", "byte": 0, "mask": 1}],
        }
        for family, defaults in (
            ("hid.descriptor", {"input": input_layout}),
            ("xbox.xusb", {"input": input_layout}),
            (
                "xbox.xid",
                {
                    "input": {
                        "report": {"length": 4},
                        "axes": [
                            {"control": "left-stick-x", "byte": 0, "symmetric": True}
                        ],
                    }
                },
            ),
            (
                "xbox.xid",
                {
                    "input": {
                        "report": {"length": 4},
                        "hat": [
                            {"encoding": "table", "byte": 2, "mask": 15, "values": {}}
                        ],
                    }
                },
            ),
            (
                "xbox.xid",
                {
                    "input": {
                        "report": {"length": 4},
                        "hat": [
                            {
                                "encoding": "table",
                                "byte": 2,
                                "mask": 15,
                                "values": {"01": "north"},
                            }
                        ],
                    }
                },
            ),
            (
                "xbox.xid",
                {
                    "input": {
                        "report": {"length": 4},
                        "hat": [
                            {
                                "encoding": "table",
                                "byte": 2,
                                "mask": 15,
                                "values": {"1": "neutral"},
                            }
                        ],
                    }
                },
            ),
            ("xbox.xid", {"output": {"startup": [self.startup_write()]}}),
            ("sony.dualsense", {"tuning": {"inputLivenessTimeoutMs": 5}}),
            ("sony.dualsense", {"tuning": {"hidStartupRecoveryRounds": 2}}),
            ("xbox.xusb", {"tuning": {"hidStartupIntervalMs": 5}}),
            ("xbox.gip", {}),
            ("xbox.gip", {"unknown": {}}),
            ("xbox.gip", {"tuning": {"stickDeadzone": 5}}),
        ):
            with self.subTest(family=family, defaults=defaults):
                self.assert_rejected(self.with_body(family, defaults=defaults))

    def test_every_family_defaults_the_frame_queue_capacity(self) -> None:
        # Swift's `UserSpaceReportSender.fallbackQueueCapacity` is 64; a Swift test keeps both.
        paths = sorted(validate_schemas.PROTOCOL_DESCRIPTIONS.glob("*.json"))
        for path in paths:
            with self.subTest(family=path.stem):
                document = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(
                    document["defaults"]["tuning"]["frameQueueCapacity"], 64
                )
                for capacity in (1, 1024):
                    document["defaults"]["tuning"]["frameQueueCapacity"] = capacity
                    self.check(document, path.name)
                for capacity in (0, 1025, 1.5, "64"):
                    document["defaults"]["tuning"]["frameQueueCapacity"] = capacity
                    self.assert_rejected(document, path.name)

    def startup_write(self) -> dict[str, Any]:
        return {"report": {"kind": "output", "id": 1, "length": 4}, "bytes": [1, 2, 3]}

    def test_rejects_signatures_for_a_family_without_variants(self) -> None:
        document = self.described("hid.descriptor", "usb")
        self.assert_rejected(document, code="E5004")

    def test_family_parameters_match_the_controller_schema(self) -> None:
        """Each family declares the parameters that controller records may set for it."""
        controller: Any = self.documents["controller.schema.json"]
        records: dict[str, set[str]] = {}
        for rule in controller["$defs"]["protocol"]["allOf"]:
            families = rule["if"]["properties"]["family"]
            names = families.get("enum") or [families.get("const")]
            if None in names:
                continue
            parameters = rule["then"]["properties"].get("parameters", {})
            for family in names:
                records.setdefault(family, set()).update(
                    parameters.get("properties", {})
                )
        for rule in self.schema["allOf"]:
            family = rule["if"]["properties"]["family"]["const"]
            declared = rule["then"]["properties"]["parameters"]
            allowed = (
                set(declared["propertyNames"]["enum"])
                if declared is not False
                else set()
            )
            with self.subTest(family=family):
                self.assertEqual(allowed, records.get(family, set()))


if __name__ == "__main__":
    unittest.main()
