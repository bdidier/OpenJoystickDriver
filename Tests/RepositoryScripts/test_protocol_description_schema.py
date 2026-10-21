from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from Scripts.Catalog import protocol_descriptions
from Scripts.Catalog.schema_header import header
from Scripts.Quality import validate_schemas
from Tests.RepositoryScripts import schema_rejections


def setUpModule() -> None:
    schema_rejections.enforce_description_rejections()


def zeros(count: int) -> str:
    return " ".join(["00"] * count)


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


# The counts a family's description sets for its driver.
SESSION_LIMITS: dict[str, dict[str, Any]] = {
    "XboxGIP": {
        "handshakeAttempts": 3,
        "announceResendLimit": 8,
        "namedPackets": [
            {"id": "XboxGIP/power-on", "bytes": "05 20 00 01 00", "sessionByte": 2}
        ],
    },
    "XboxXUSB": {"receiverInquiryResendLimit": 8},
    "NintendoSwitch2": {
        "commandChannel": {
            "interface": 1,
            "inEndpoint": 130,
            "replyLength": 80,
            "usbReplyTimeoutMilliseconds": 100,
            "bluetoothLEReplyTimeoutMilliseconds": 500,
        },
        "trailingStopPackets": 2,
    },
}


# The activation and deactivation reports each Valve family's description must state.
VALVE_FAMILIES = ("ValveSteamController", "ValveSteamDeck", "ValveSteamTriton")
VALVE_SESSION: dict[str, Any] = {
    "activation": [
        {"report": {"kind": "Feature", "id": 0, "length": 2}, "bytes": "81 00"}
    ],
    "deactivation": [
        {"report": {"kind": "Feature", "id": 0, "length": 2}, "bytes": "85 00"}
    ],
}


def xusb_description() -> dict[str, Any]:
    return {
        **header("ProtocolDescription"),
        "family": "XboxXUSB",
        "name": "Xbox 360 (XUSB)",
        "variants": ["Wired", "Receiver"],
        "storesVariant": True,
        "endpoints": {"in": 129, "out": 1},
        "rawUSB": True,
        "interfaceSignatures": [
            {
                "variant": "Wired",
                "interfaceClass": 255,
                "interfaceSubclass": 93,
                "interfaceProtocol": 1,
            }
        ],
        "defaults": {"session": dict(SESSION_LIMITS["XboxXUSB"])},
    }


def with_variant_facts(document: dict[str, Any]) -> dict[str, Any]:
    """The document with its family's `name`, its `variants` and `storesVariant` when it states
    neither, and its `sessionKeys` when it states none, so a test that varies something else need not repeat
    them."""
    facts = protocol_descriptions.bundled().get(str(document.get("family")), {})
    if "name" not in document and "name" in facts:
        document = {"name": facts["name"], **document}
    if "sessionKeys" not in document and "sessionKeys" in facts:
        document = {"sessionKeys": facts["sessionKeys"], **document}
    if "variants" in document or "storesVariant" in document:
        return document
    return {
        **{key: facts[key] for key in ("variants", "storesVariant") if key in facts},
        **document,
    }


# The facts a description states about its family, which the schema ties its defaults to.
FAMILY_FACTS: dict[str, dict[str, Any]] = {
    "HIDReportLayout": {"recordSections": ["input", "rumble"]},
    "XboxGIP": {"rawUSB": True},
    "XboxXID": {"rawUSB": True, "recordSections": ["input", "rumble"]},
    "XboxXUSB": {"rawUSB": True},
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
        document = with_variant_facts(document)
        path = self.root / (
            name
            or f"{
                protocol_descriptions.file_stems().get(
                    str(document.get('family')), str(document.get('family'))
                )
            }.json"
        )
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
            sorted(protocol_descriptions.file_stems().values()),
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
            ("apiVersion", "unsupported.example/v9"),
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

    def test_rejects_a_missing_or_empty_name(self) -> None:
        for name in (None, ""):
            with self.subTest(name=name):
                document = xusb_description()
                if name is None:
                    del document["name"]
                else:
                    document["name"] = name
                path = self.root / "xbox-xusb.json"
                path.write_text(json.dumps(document), encoding="utf-8")
                with self.assertRaisesRegex(
                    validate_schemas.ValidationError, r"^E5002: "
                ):
                    validate_schemas.validate_protocol_descriptions(
                        self.schema, self.registry, [path]
                    )

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
        family_delta = xusb_description()
        family_delta["defaults"] = {"capabilities": {"rumble": "Absent"}}
        self.assert_rejected(family_delta)

    def test_rejects_a_duplicate_signature(self) -> None:
        document = xusb_description()
        signatures = document["interfaceSignatures"]
        signatures.append(copy.deepcopy(signatures[0]))
        self.assert_rejected(document)

    def family_rules(self) -> list[Any]:
        """The per-family rules; the other `allOf` rules name no family."""
        return [
            rule
            for rule in self.schema["allOf"]
            if "family" in rule["if"].get("properties", {})
        ]

    def family_variants(self) -> dict[str, list[str]]:
        """Each family's variants, as its bundled description lists them."""
        return {
            family: protocol_descriptions.family_variants(description)
            for family, description in protocol_descriptions.bundled().items()
        }

    def described(self, family: str, variant: str) -> dict[str, Any]:
        document = xusb_description()
        document["family"] = family
        document["interfaceSignatures"][0]["variant"] = variant
        document.pop("variants")
        document.pop("storesVariant")
        document.pop("defaults")
        if family == "NintendoSwitch1":
            document["defaults"] = {"session": {"subcommands": self.subcommands()}}
        elif family in SESSION_LIMITS:
            document["defaults"] = {"session": dict(SESSION_LIMITS[family])}
        elif family in VALVE_FAMILIES:
            document["defaults"] = {"session": dict(VALVE_SESSION)}
        return document

    def test_every_family_lists_its_variants(self) -> None:
        families = self.family_variants()
        controller: Any = self.documents["controller.schema.json"]
        self.assertEqual(
            sorted(families),
            sorted(controller["$defs"]["protocol"]["properties"]["family"]["enum"]),
        )
        self.assertEqual(families["SonyDualShock4"], ["USB", "BluetoothClassic"])
        self.assertEqual(families["HIDDescriptor"], [])

    def test_stored_variants_are_a_family_fact(self) -> None:
        stores = {
            family
            for family, description in protocol_descriptions.bundled().items()
            if protocol_descriptions.stores_variant(description)
        }
        self.assertEqual(
            stores,
            {
                "XboxXID",
                "XboxXUSB",
                "ValveSteamController",
                "ValveSteamTriton",
                "VendorGameSir",
            },
        )
        self.assertIsNone(
            protocol_descriptions.stored_variant_problem("XboxXUSB", "Wired")
        )
        for family, variant in (
            ("XboxXUSB", None),
            ("XboxXUSB", "USB"),
            ("XboxGIP", "USB"),
            ("HIDDescriptor", "USB"),
        ):
            with self.subTest(family=family, variant=variant):
                self.assertRegex(
                    protocol_descriptions.stored_variant_problem(family, variant) or "",
                    "stored variant",
                )

    def test_rejects_stores_variant_without_variants(self) -> None:
        document = xusb_description()
        document.pop("variants")
        self.assert_rejected(document)

    def test_rejects_an_unknown_or_repeated_variant_list(self) -> None:
        for variants in (["Wired", "Wired"], ["usb"], []):
            with self.subTest(variants=variants):
                document = xusb_description()
                document["variants"] = variants
                self.assert_rejected(document)

    def test_each_family_accepts_only_its_own_variants(self) -> None:
        every = self.schema["$defs"]["variant"]["enum"]
        for family, allowed in self.family_variants().items():
            for variant in every:
                with self.subTest(family=family, variant=variant):
                    document = self.described(family, variant)
                    if variant in allowed:
                        self.check(document)
                    else:
                        self.assert_rejected(document, code="E5004")

    def test_rejects_a_family_spelled_as_before_the_naming_rule(self) -> None:
        for old in ("xbox.xusb", "hid.descriptor", "vendor.ps3-third-party"):
            with self.subTest(family=old):
                self.assert_rejected({**xusb_description(), "family": old})

    def test_rejects_descriptions_values_spelled_as_before_the_naming_rule(
        self,
    ) -> None:
        valid = {
            "parameter type": (
                "SonyDualSense",
                {"parameters": {"maker": {"type": "Enum", "values": ["ThirdParty"]}}},
            ),
            "controls base": ("XboxXID", {"controls": {"base": "Xbox"}}),
        }
        invalid = {
            "parameter type enum": (
                "SonyDualSense",
                {"parameters": {"maker": {"type": "enum", "values": ["ThirdParty"]}}},
            ),
            "parameter type flag": (
                "SonyDualSense",
                {"parameters": {"forcedVibration": {"type": "flag"}}},
            ),
            "integer field type": (
                "XboxGIP",
                {
                    "parameters": {
                        "shareButton": {
                            "type": "Object",
                            "fields": {
                                "fromEnd": {
                                    "type": "integer",
                                    "minimum": 1,
                                    "maximum": 255,
                                }
                            },
                        }
                    }
                },
            ),
            "controls base": ("XboxXID", {"controls": {"base": "xbox"}}),
        }
        for label, (family, members) in valid.items():
            with self.subTest(label):
                self.check(self.with_body(family, **members))
        for label, (family, members) in invalid.items():
            with self.subTest(label):
                self.assert_rejected(self.with_body(family, **members))

    def test_rejects_a_variant_spelled_as_before_the_naming_rule(self) -> None:
        for old in ("usb", "bluetooth-le", "enhanced-hid"):
            with self.subTest(variant=old):
                self.assert_rejected(self.described("XboxGIP", old), code="E5004")

    # Parameters and defaults.

    def with_body(self, family: str, **members: Any) -> dict[str, Any]:
        facts: dict[str, Any] = FAMILY_FACTS.get(family, {})
        document = {
            **header("ProtocolDescription"),
            "family": family,
            "endpoints": {"in": 130, "out": 2},
            **facts,
            **members,
        }
        if limits := SESSION_LIMITS.get(family):
            defaults = dict(document.get("defaults", {}))
            defaults["session"] = {**limits, **defaults.get("session", {})}
            document["defaults"] = defaults
        if family in VALVE_FAMILIES:
            defaults = dict(document.get("defaults", {}))
            defaults["session"] = {**VALVE_SESSION, **defaults.get("session", {})}
            document["defaults"] = defaults
        if family == "NintendoSwitch1":
            defaults = dict(document.get("defaults", {}))
            defaults["session"] = {
                "subcommands": self.subcommands(),
                **defaults.get("session", {}),
            }
            document["defaults"] = defaults
        return document

    def test_accepts_parameters_and_defaults(self) -> None:
        self.check(
            self.with_body(
                "SonyDualSense",
                parameters={
                    "maker": {"type": "Enum", "values": ["ThirdParty"]},
                    "forcedVibration": {"type": "Flag"},
                },
                defaults={"tuning": {"stickDeadzone": 0.1}},
            )
        )
        self.check(
            self.with_body(
                "XboxGIP",
                parameters={
                    "shareButton": {
                        "type": "Object",
                        "fields": {
                            "fromEnd": {
                                "type": "Integer",
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
                "HIDReportLayout",
                defaults={
                    "input": {
                        "report": {"length": 1},
                        "buttons": [{"control": "South", "byte": 0, "mask": 1}],
                    }
                },
            )
        )
        self.check(
            self.with_body(
                "XboxXID",
                defaults={
                    "input": {
                        "report": {"length": 4},
                        "axes": [
                            {
                                "control": "LeftStickX",
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
                                "encoding": "Table",
                                "byte": 2,
                                "mask": 15,
                                "values": {"1": "North", "9": "NorthEast"},
                            }
                        ],
                    }
                },
            )
        )

    def test_rejects_a_bad_parameter_declaration(self) -> None:
        for declaration in (
            {"type": "string"},
            {"type": "Flag", "values": ["A"]},
            {"type": "Enum"},
            {"type": "Enum", "values": []},
            {"type": "Enum", "values": ["lower"]},
            {"type": "Enum", "values": ["A", "A"]},
            {"type": "Object", "fields": {}},
            {"type": "Object", "fields": {"x": {"type": "Integer", "minimum": 1}}},
            {"type": "Object", "fields": {"x": {"type": "string"}}},
        ):
            with self.subTest(declaration=declaration):
                self.assert_rejected(
                    self.with_body("SonyDualSense", parameters={"maker": declaration})
                )

    def test_rejects_a_parameter_the_family_does_not_declare(self) -> None:
        flag = {"type": "Flag"}
        self.assert_rejected(self.with_body("SonyDualSense", parameters={"x": flag}))
        self.assert_rejected(self.with_body("SonyDualSense", parameters={}))
        for family, name in (
            ("SonyDualSense", "layout"),
            ("XboxGIP", "maker"),
            ("XboxXID", "layout"),
            ("NintendoSwitch2", "usbProtocol"),
        ):
            with self.subTest(family=family, name=name):
                self.assert_rejected(self.with_body(family, parameters={name: flag}))

    def test_a_family_specific_session_field_of_another_family_is_refused(
        self,
    ) -> None:
        samples = self.session_field_samples()
        owners = {
            "subcommands": "NintendoSwitch1",
            "namedPackets": "XboxGIP",
            "handshakeAttempts": "XboxGIP",
            "announceResendLimit": "XboxGIP",
            "receiverInquiryResendLimit": "XboxXUSB",
            "commandChannel": "NintendoSwitch2",
            "trailingStopPackets": "NintendoSwitch2",
            "activation": "ValveSteamDeck",
            "deactivation": "ValveSteamDeck",
        }
        self.assertEqual(set(samples), set(owners))
        for key, owner in owners.items():
            for family in ("XboxXID", "SonyDualSense", "NintendoSwitchInputOnly"):
                with self.subTest(family=family, key=key):
                    document = self.with_body(family)
                    document.setdefault("defaults", {}).setdefault("session", {})[
                        key
                    ] = samples[key]
                    self.assert_rejected(document)
            with self.subTest(family="another owner", key=key):
                other = "XboxXUSB" if owner != "XboxXUSB" else "XboxGIP"
                document = self.with_body(other)
                document["defaults"]["session"][key] = samples[key]
                self.assert_rejected(document)

    def test_a_session_field_the_driver_reads_must_be_set(self) -> None:
        read = {
            **{family: set(limits) for family, limits in SESSION_LIMITS.items()},
            "NintendoSwitch1": {"subcommands"},
            **{family: {"activation", "deactivation"} for family in VALVE_FAMILIES},
        }
        for family, keys in read.items():
            for key in sorted(keys):
                with self.subTest(family=family, key=key):
                    document = self.with_body(family)
                    del document["defaults"]["session"][key]
                    self.assert_rejected(document)

    def session_field_samples(self) -> dict[str, Any]:
        return {
            **SESSION_LIMITS["XboxGIP"],
            **SESSION_LIMITS["XboxXUSB"],
            **SESSION_LIMITS["NintendoSwitch2"],
            **VALVE_SESSION,
            "subcommands": self.subcommands(),
        }

    def test_session_limits_are_accepted_for_their_family(self) -> None:
        for family in SESSION_LIMITS:
            with self.subTest(family=family):
                self.check(self.with_body(family))

    def test_command_channel_has_ranges(self) -> None:
        def channel_with(path: tuple[str, ...], value: Any) -> dict[str, Any]:
            document = copy.deepcopy(self.with_body("NintendoSwitch2"))
            target = document["defaults"]["session"]["commandChannel"]
            for key in path[:-1]:
                target = target[key]
            target[path[-1]] = value
            return document

        for path, low, high in (
            (("interface",), 0, 255),
            (("inEndpoint",), 128, 255),
            (("replyLength",), 1, 4096),
            (("usbReplyTimeoutMilliseconds",), 1, 60000),
            (("bluetoothLEReplyTimeoutMilliseconds",), 1, 60000),
        ):
            for value in (low, high):
                with self.subTest(path=path, value=value):
                    self.check(channel_with(path, value))
            for value in (low - 1, high + 1):
                with self.subTest(path=path, value=value):
                    self.assert_rejected(channel_with(path, value))
            with self.subTest(path=path, case="required"):
                missing = channel_with(path, 1)
                target = missing["defaults"]["session"]["commandChannel"]
                for key in path[:-1]:
                    target = target[key]
                del target[path[-1]]
                self.assert_rejected(missing)
        with self.subTest(case="unknown channel member"):
            self.assert_rejected(channel_with(("outEndpoint",), 2))

    def test_session_limits_have_ranges(self) -> None:
        for family, key, low, high in (
            ("XboxGIP", "handshakeAttempts", 1, 10),
            ("XboxGIP", "announceResendLimit", 1, 100),
            ("XboxXUSB", "receiverInquiryResendLimit", 1, 100),
            ("NintendoSwitch2", "trailingStopPackets", 1, 10),
        ):
            for value in (low, high):
                with self.subTest(key=key, value=value):
                    document = self.with_body(family)
                    document["defaults"]["session"][key] = value
                    self.check(document)
            for value in (low - 1, high + 1):
                with self.subTest(key=key, value=value):
                    document = self.with_body(family)
                    document["defaults"]["session"][key] = value
                    self.assert_rejected(document)

    def test_rejects_defaults_a_driver_does_not_read(self) -> None:
        input_layout = {
            "report": {"length": 1},
            "buttons": [{"control": "South", "byte": 0, "mask": 1}],
        }
        for family, defaults in (
            ("HIDDescriptor", {"input": input_layout}),
            ("XboxXUSB", {"input": input_layout}),
            (
                "XboxXID",
                {
                    "input": {
                        "report": {"length": 4},
                        "axes": [
                            {"control": "LeftStickX", "byte": 0, "symmetric": True}
                        ],
                    }
                },
            ),
            (
                "XboxXID",
                {
                    "input": {
                        "report": {"length": 4},
                        "hat": [
                            {"encoding": "Table", "byte": 2, "mask": 15, "values": {}}
                        ],
                    }
                },
            ),
            (
                "XboxXID",
                {
                    "input": {
                        "report": {"length": 4},
                        "hat": [
                            {
                                "encoding": "Table",
                                "byte": 2,
                                "mask": 15,
                                "values": {"01": "North"},
                            }
                        ],
                    }
                },
            ),
            (
                "XboxXID",
                {
                    "input": {
                        "report": {"length": 4},
                        "hat": [
                            {
                                "encoding": "Table",
                                "byte": 2,
                                "mask": 15,
                                "values": {"1": "Neutral"},
                            }
                        ],
                    }
                },
            ),
            ("XboxXID", {"session": {"startup": [self.startup_write()]}}),
            ("SonyDualSense", {"tuning": {"inputLivenessTimeoutMs": 5}}),
            ("SonyDualSense", {"tuning": {"hidStartupRecoveryRounds": 2}}),
            ("XboxXUSB", {"tuning": {"hidStartupIntervalMs": 5}}),
            ("XboxGIP", {"unknown": {}}),
            ("XboxGIP", {"tuning": {"stickDeadzone": 5}}),
            ("XboxGIP", {"session": {"rumble": self.rumble_template()}}),
            ("XboxXUSB", {"session": {"rumble": self.rumble_template()}}),
        ):
            with self.subTest(family=family, defaults=defaults):
                self.assert_rejected(self.with_body(family, defaults=defaults))

    def rumble_template(self) -> dict[str, Any]:
        return {
            "report": {"kind": "Output", "id": 1, "length": 4},
            "lowFrequency": {"byte": 1},
        }

    def test_every_family_may_set_a_frame_queue_capacity_in_the_schema_range(
        self,
    ) -> None:
        # The default is the schema's; no description repeats it.
        paths = sorted(validate_schemas.PROTOCOL_DESCRIPTIONS.glob("*.json"))
        for path in paths:
            with self.subTest(family=path.stem):
                document = json.loads(path.read_text(encoding="utf-8"))
                tuning = document.setdefault("defaults", {}).setdefault("tuning", {})
                self.assertNotIn("frameQueueCapacity", tuning)
                for capacity in (1, 1024):
                    tuning["frameQueueCapacity"] = capacity
                    self.check(document, path.name)
                for capacity in (0, 1025, 1.5, "64"):
                    tuning["frameQueueCapacity"] = capacity
                    self.assert_rejected(document, path.name)

    def startup_write(self) -> dict[str, Any]:
        return {"report": {"kind": "Output", "id": 1, "length": 4}, "bytes": "01 02 03"}

    def usb_write(self, **members: Any) -> dict[str, Any]:
        return {"bytes": "05 20 00 01 00", **members}

    def hid_write(self, **members: Any) -> dict[str, Any]:
        return {**self.startup_write(), **members}

    def test_accepts_startup_writes_a_family_carries(self) -> None:
        for family, write in (
            (
                "XboxGIP",
                self.usb_write(endpoint=2, timeoutMilliseconds=2000, sessionByte=2),
            ),
            ("XboxXUSB", self.usb_write(delayMilliseconds=0, toleratesRejection=True)),
            ("SonyDualShock4", self.hid_write(phase="Startup", delayMilliseconds=5)),
            (
                "SonyDualShock4",
                self.hid_write(
                    report={"kind": "Output", "id": 17, "length": 78},
                    bytes=zeros(73),
                    crc32Seed=162,
                    variants=["BluetoothClassic"],
                ),
            ),
        ):
            with self.subTest(family=family, write=write):
                self.check(
                    self.with_body(family, defaults={"session": {"startup": [write]}})
                )

    def test_rejects_malformed_startup_writes(self) -> None:
        for family, write in (
            ("XboxGIP", self.usb_write(endpoint=0)),
            ("XboxGIP", self.usb_write(endpoint=128)),
            ("XboxGIP", self.usb_write(timeoutMilliseconds=0)),
            ("XboxGIP", self.usb_write(timeoutMilliseconds=60001)),
            ("XboxGIP", self.usb_write(delayMilliseconds=1001)),
            ("XboxGIP", self.usb_write(delayMilliseconds=-1)),
            ("XboxGIP", self.usb_write(sessionByte=64)),
            ("XboxGIP", self.usb_write(bytes=zeros(65))),
            ("XboxGIP", self.usb_write(bytes="")),
            ("XboxGIP", self.usb_write(toleratesRejection="yes")),
            (
                "XboxGIP",
                self.usb_write(report={"kind": "Output", "id": 1, "length": 4}),
            ),
            ("SonyDualShock4", self.hid_write(phase="Later")),
            ("SonyDualShock4", self.hid_write(delayMilliseconds=1001)),
            ("SonyDualShock4", self.hid_write(crc32Seed=256)),
            ("SonyDualShock4", self.hid_write(crc32Seed=1)),
            (
                "SonyDualShock4",
                self.hid_write(report={"kind": "Output", "id": 1, "length": 129}),
            ),
            ("SonyDualShock4", self.hid_write(variants=[])),
            ("SonyDualShock4", self.hid_write(variants=["USB", "USB"])),
            ("SonyDualShock4", self.hid_write(when={"parameter": "layout"})),
            (
                "SonyDualShock4",
                self.hid_write(when={"parameter": "role", "is": ["A"], "isNot": ["B"]}),
            ),
            ("SonyDualShock4", self.hid_write(when={"parameter": "role", "is": []})),
            (
                "SonyDualShock4",
                self.hid_write(when={"parameter": "color", "is": ["A"]}),
            ),
        ):
            with self.subTest(family=family, write=write):
                self.assert_rejected(
                    self.with_body(family, defaults={"session": {"startup": [write]}})
                )

    def test_rejects_startup_writes_mixing_hid_and_usb_formats(self) -> None:
        self.assert_rejected(
            self.with_body(
                "SonyDualShock4",
                defaults={"session": {"startup": [self.hid_write(), self.usb_write()]}},
            )
        )

    def test_rejects_hid_startup_writes_for_a_raw_usb_family(self) -> None:
        self.assert_rejected(
            self.with_body(
                "XboxGIP", defaults={"session": {"startup": [self.hid_write()]}}
            )
        )

    def test_rejects_a_startup_write_naming_what_the_family_lacks(self) -> None:
        role = {"role": {"type": "Enum", "values": ["WirelessAdapter"]}}
        for write, code in (
            (self.usb_write(variants=["Wired"]), "E5004"),
            (self.usb_write(when={"parameter": "layout", "is": ["Pro"]}), "E5002"),
            (self.usb_write(when={"parameter": "role", "is": ["Other"]}), "E5002"),
        ):
            with self.subTest(write=write):
                self.assert_rejected(
                    self.with_body(
                        "SonyDualShock4",
                        parameters=role,
                        defaults={"session": {"startup": [write]}},
                    ),
                    code=code,
                )

    def keep_alive_body(self, family: str, keep_alive: Any, **members: Any) -> Any:
        """A description of `family` that carries `keep_alive` in `defaults.session`."""
        keys = {
            "VendorGameSir": {"rawUSB": ["USB"]},
            "ValveSteamTriton": {"tuningKeys": ["lizardResendTicks"]},
        }
        defaults = {"session": {"keepAlive": keep_alive}}
        if family == "ValveSteamTriton":
            defaults["tuning"] = {"lizardResendTicks": 75}
        return self.with_body(
            family, **keys.get(family, {}), defaults=defaults, **members
        )

    def test_accepts_keep_alives_a_family_carries(self) -> None:
        feature = {"kind": "Feature", "id": 1, "length": 64}
        for family, keep_alive in (
            ("XboxGIP", {"intervalMilliseconds": 4000}),
            (
                "XboxGIP",
                {
                    "intervalMilliseconds": 1,
                    "writes": [
                        self.usb_write(endpoint=2, timeoutMilliseconds=5, sessionByte=2)
                    ],
                },
            ),
            (
                "VendorGameSir",
                {
                    "intervalMilliseconds": 60000,
                    "writes": [
                        self.usb_write(variants=["USB"]),
                        self.hid_write(variants=["EnhancedHID"]),
                    ],
                },
            ),
            (
                "ValveSteamTriton",
                {
                    "intervalMilliseconds": 40,
                    "writes": [
                        {
                            "report": feature,
                            "bytes": zeros(63),
                            "resendTuning": "lizardResendTicks",
                        }
                    ],
                },
            ),
        ):
            with self.subTest(family=family, keep_alive=keep_alive):
                self.check(self.keep_alive_body(family, keep_alive))

    def test_rejects_malformed_keep_alives(self) -> None:
        usb = self.usb_write()
        for keep_alive in (
            {},
            {"writes": [usb]},
            {"intervalMilliseconds": 0},
            {"intervalMilliseconds": 60001},
            {"intervalMilliseconds": 1.5},
            {"intervalMilliseconds": "500"},
            {"intervalMilliseconds": 500, "unknown": 1},
            {"intervalMilliseconds": 500, "writes": []},
            {"intervalMilliseconds": 500, "writes": [usb] * 9},
            {"intervalMilliseconds": 500, "writes": [self.usb_write(bytes="")]},
            {"intervalMilliseconds": 500, "writes": [self.usb_write(bytes=zeros(65))]},
            {"intervalMilliseconds": 500, "writes": [self.usb_write(sessionByte=64)]},
            {"intervalMilliseconds": 500, "writes": [self.usb_write(endpoint=0)]},
            {"intervalMilliseconds": 500, "writes": [self.usb_write(variants=[])]},
            {"intervalMilliseconds": 500, "writes": [self.usb_write(resendTuning="x")]},
            {
                "intervalMilliseconds": 500,
                "writes": [self.usb_write(resendTuning="usbCommandTimeoutMs")],
            },
        ):
            with self.subTest(keep_alive=keep_alive):
                self.assert_rejected(self.keep_alive_body("XboxGIP", keep_alive))

    # Switch 1 subcommands.

    @staticmethod
    def spi_read(**members: Any) -> dict[str, Any]:
        return {
            "subcommand": 16,
            "spiRead": {
                "address": 24608,
                "length": 24,
                "purpose": "FactoryMotionCalibration",
                **members,
            },
        }

    def subcommand_body(self, subcommands: Any, family: str = "NintendoSwitch1") -> Any:
        return self.with_body(
            family, defaults={"session": {"subcommands": subcommands}}
        )

    @staticmethod
    def subcommands(**members: Any) -> dict[str, Any]:
        return {
            "reportID": 1,
            "counterModulus": 16,
            "requests": [{"subcommand": 3, "data": "30"}],
            "playerIndicator": {
                "subcommand": 48,
                "patterns": {
                    "off": 0,
                    "player1": 1,
                    "player2": 3,
                    "player3": 7,
                    "player4": 15,
                },
            },
            **members,
        }

    @staticmethod
    def patterns(**members: Any) -> dict[str, Any]:
        return {
            "off": 0,
            "player1": 1,
            "player2": 3,
            "player3": 7,
            "player4": 15,
            **members,
        }

    def test_accepts_player_indicator_patterns(self) -> None:
        for patterns in (self.patterns(), self.patterns(off=255, player4=0)):
            with self.subTest(patterns=patterns):
                self.check(
                    self.subcommand_body(
                        self.subcommands(
                            playerIndicator={"subcommand": 255, "patterns": patterns}
                        )
                    )
                )

    def test_accepts_subcommands(self) -> None:
        plain = {"subcommand": 3, "data": "30"}
        for subcommands in (
            self.subcommands(),
            self.subcommands(counterModulus=2),
            self.subcommands(counterModulus=256),
            self.subcommands(requests=[plain] * 16),
            self.subcommands(requests=[plain, self.spi_read()]),
            self.subcommands(
                requests=[
                    self.spi_read(),
                    self.spi_read(purpose="UserMotionCalibration", address=0, length=1),
                ]
            ),
            self.subcommands(requests=[self.spi_read(address=4294967295, length=29)]),
        ):
            with self.subTest(subcommands=subcommands):
                self.check(self.subcommand_body(subcommands))

    def test_rejects_malformed_subcommands(self) -> None:
        plain = {"subcommand": 3, "data": "30"}
        both = {**plain, "spiRead": self.spi_read()["spiRead"]}
        for subcommands in (
            {"counterModulus": 16, "requests": [plain]},
            {"reportID": 1, "requests": [plain]},
            {"reportID": 1, "counterModulus": 16},
            {"reportID": 1, "counterModulus": 16, "requests": [plain]},
            self.subcommands(reportID=256),
            self.subcommands(counterModulus=1),
            self.subcommands(counterModulus=257),
            self.subcommands(counterModulus=16.5),
            self.subcommands(requests=[]),
            self.subcommands(requests=[plain] * 17),
            self.subcommands(unknown=1),
            self.subcommands(requests=[{"subcommand": 3}]),
            self.subcommands(requests=[both]),
            self.subcommands(requests=[{"subcommand": 256, "data": "01"}]),
            self.subcommands(requests=[{"subcommand": 3, "data": ""}]),
            self.subcommands(requests=[{"subcommand": 3, "data": zeros(17)}]),
            self.subcommands(requests=[{"subcommand": 3, "data": "100"}]),
            self.subcommands(requests=[{**plain, "unknown": 1}]),
            self.subcommands(requests=[self.spi_read(length=0)]),
            self.subcommands(requests=[self.spi_read(length=30)]),
            self.subcommands(requests=[self.spi_read(address=-1)]),
            self.subcommands(requests=[self.spi_read(address=4294967296)]),
            self.subcommands(requests=[self.spi_read(purpose="other")]),
            self.subcommands(requests=[self.spi_read(unknown=1)]),
            self.subcommands(playerIndicator={"subcommand": 48}),
            self.subcommands(playerIndicator={"patterns": self.patterns()}),
            self.subcommands(
                playerIndicator={"subcommand": 256, "patterns": self.patterns()}
            ),
            self.subcommands(
                playerIndicator={"subcommand": 48, "patterns": self.patterns(off=256)}
            ),
            self.subcommands(
                playerIndicator={"subcommand": 48, "patterns": self.patterns(off=-1)}
            ),
            self.subcommands(
                playerIndicator={
                    "subcommand": 48,
                    "patterns": self.patterns(player5=1),
                }
            ),
            self.subcommands(
                playerIndicator={"subcommand": 48, "patterns": {"off": 0, "player1": 1}}
            ),
            self.subcommands(
                playerIndicator={
                    "subcommand": 48,
                    "patterns": self.patterns(),
                    "unknown": 1,
                }
            ),
            # Each purpose appears at most once.
            self.subcommands(requests=[self.spi_read(), self.spi_read(address=1)]),
        ):
            with self.subTest(subcommands=subcommands):
                self.assert_rejected(self.subcommand_body(subcommands))

    # Valve activation and deactivation.

    @staticmethod
    def session_write(**members: Any) -> dict[str, Any]:
        return {
            "report": {"kind": "Feature", "id": 0, "length": 2},
            "bytes": "81 00",
            **members,
        }

    def valve_body(self, family: str, **session: Any) -> dict[str, Any]:
        transports: dict[str, Any] = (
            {"writeTransports": ["USB", "BluetoothLE"]}
            if family == "ValveSteamController"
            else {}
        )
        return self.with_body(family, defaults={"session": session}, **transports)

    def test_accepts_valve_activation_and_deactivation(self) -> None:
        for family in VALVE_FAMILIES:
            with self.subTest(family=family):
                self.check(self.valve_body(family))
        self.check(
            self.valve_body(
                "ValveSteamController",
                activation=[
                    self.session_write(transport="USB"),
                    self.session_write(
                        report={"kind": "Feature", "id": 3, "length": 4},
                        bytes="C0 81 00",
                        transport="BluetoothLE",
                    ),
                ],
            )
        )

    def test_rejects_malformed_valve_activation(self) -> None:
        for writes in (
            [],
            [self.session_write() for _ in range(17)],
            [self.session_write(bytes="81")],
            [self.session_write(bytes="81 00 00")],
            [self.session_write(transport="Radio")],
            [self.session_write(phase="Startup")],
            [self.session_write(variants=["Wired"])],
            [self.session_write(delayMilliseconds=5)],
            [{"bytes": "81 00"}],
            [{"report": {"kind": "Feature", "id": 0, "length": 2}}],
        ):
            for key in ("activation", "deactivation"):
                with self.subTest(key=key, writes=writes):
                    self.assert_rejected(
                        self.valve_body("ValveSteamDeck", **{key: writes})
                    )

    def test_activation_transport_is_only_one_writeTransports_lists(self) -> None:
        for family, transport, accepted in (
            ("ValveSteamController", "USB", True),
            ("ValveSteamController", "BluetoothLE", True),
            ("ValveSteamController", "BluetoothClassic", False),
            ("ValveSteamDeck", "USB", False),
            ("ValveSteamTriton", "BluetoothLE", False),
        ):
            for key in ("activation", "deactivation"):
                with self.subTest(family=family, key=key, transport=transport):
                    document = self.valve_body(
                        family, **{key: [self.session_write(transport=transport)]}
                    )
                    if accepted:
                        self.check(document)
                    else:
                        self.assert_rejected(document)

    # GIP named packets.

    @staticmethod
    def named_packet(**members: Any) -> dict[str, Any]:
        return {
            "id": "XboxGIP/power-on",
            "bytes": "05 20 00 01 00",
            "sessionByte": 2,
            **members,
        }

    def named_packet_body(self, packets: Any, family: str = "XboxGIP") -> Any:
        return self.with_body(family, defaults={"session": {"namedPackets": packets}})

    def test_accepts_named_packets(self) -> None:
        for packets in (
            [self.named_packet()],
            [self.named_packet(), self.named_packet(id="XboxGIP/led-on")],
            [self.named_packet(id=f"XboxGIP/packet-{i}") for i in range(16)],
            [self.named_packet(bytes="00 00 00")],
            [self.named_packet(bytes=zeros(64))],
        ):
            with self.subTest(packets=packets):
                self.check(self.named_packet_body(packets))

    def test_rejects_malformed_named_packets(self) -> None:
        for packets in (
            [],
            [self.named_packet(id=f"XboxGIP/packet-{i}") for i in range(17)],
            [{"bytes": "05 20 00", "sessionByte": 2}],
            [{"id": "XboxGIP/power-on", "sessionByte": 2}],
            [{"id": "XboxGIP/power-on", "bytes": "05 20 00"}],
            [self.named_packet(id="power-on")],
            [self.named_packet(id="XboxGIP/Power-On")],
            [self.named_packet(id="XboxGIP/power--on")],
            [self.named_packet(id="XboxGIP/")],
            [self.named_packet(bytes="05 20")],
            [self.named_packet(bytes=zeros(65))],
            [self.named_packet(bytes="05 20 100")],
            [self.named_packet(sessionByte=1)],
            [self.named_packet(sessionByte=3)],
            [self.named_packet(endpoint=2)],
            [self.named_packet(unknown=1)],
            # Each id appears at most once, and starts with the family name.
            [self.named_packet(), self.named_packet(bytes="05 20 00 02")],
            [self.named_packet(id="XboxXUSB/power-on")],
        ):
            with self.subTest(packets=packets):
                self.assert_rejected(self.named_packet_body(packets))

    def test_the_bundled_gip_description_names_the_eight_packets(self) -> None:
        packets = protocol_descriptions.bundled()["XboxGIP"]["defaults"]["session"][
            "namedPackets"
        ]
        self.assertEqual(
            [packet["id"] for packet in packets],
            [
                "XboxGIP/power-on",
                "XboxGIP/s-init",
                "XboxGIP/enable-extra-input",
                "XboxGIP/hori-ack",
                "XboxGIP/led-on",
                "XboxGIP/auth-done",
                "XboxGIP/rumble-begin",
                "XboxGIP/rumble-end",
            ],
        )

    def test_a_record_names_only_packets_the_description_defines(self) -> None:
        description = protocol_descriptions.bundled()["XboxGIP"]
        self.assertIsNone(
            protocol_descriptions.initialization_problem(
                description, ["XboxGIP/hori-ack", "XboxGIP/power-on"]
            )
        )
        self.assertIsNone(protocol_descriptions.initialization_problem(description, []))
        self.assertIn(
            "XboxGIP/missing",
            protocol_descriptions.initialization_problem(
                description, ["XboxGIP/power-on", "XboxGIP/missing"]
            )
            or "",
        )
        without = {
            key: value for key, value in description.items() if key != "defaults"
        }
        self.assertIsNotNone(
            protocol_descriptions.initialization_problem(without, ["XboxGIP/power-on"])
        )

    def packet_startup_body(self, startup: Any, family: str = "XboxGIP") -> Any:
        return self.with_body(
            family,
            defaults={
                "session": {
                    "namedPackets": [self.named_packet()],
                    "startup": startup,
                },
            },
        )

    def test_accepts_startup_that_refers_to_named_packets(self) -> None:
        for startup in (
            [{"packet": "XboxGIP/power-on"}],
            [{"packet": "XboxGIP/power-on"}, {"packet": "XboxGIP/power-on"}],
            [{"packet": "XboxGIP/power-on", "variants": ["USB"]}],
        ):
            with self.subTest(startup=startup):
                self.check(self.packet_startup_body(startup))

    def test_rejects_startup_that_refers_to_an_unknown_packet(self) -> None:
        self.assert_rejected(
            self.packet_startup_body([{"packet": "XboxGIP/missing"}]), code="E5002"
        )

    def test_rejects_malformed_or_mixed_packet_startup(self) -> None:
        for startup in (
            [{"packet": "power-on"}],
            [{"packet": "XboxGIP/power-on", "bytes": "01 02 03"}],
            [{"packet": "XboxGIP/power-on"}, self.usb_write()],
            [self.usb_write(), {"packet": "XboxGIP/power-on"}],
            [{"packet": "XboxGIP/power-on"}, self.hid_write()],
        ):
            with self.subTest(startup=startup):
                self.assert_rejected(self.packet_startup_body(startup))

    def test_the_bundled_gip_startup_refers_to_named_packets_only(self) -> None:
        description = protocol_descriptions.bundled()["XboxGIP"]
        self.assertEqual(
            [
                write["packet"]
                for write in description["defaults"]["session"]["startup"]
            ],
            ["XboxGIP/power-on", "XboxGIP/led-on", "XboxGIP/auth-done"],
        )

    def test_rejects_startup_only_members_in_a_keep_alive_write(self) -> None:
        for write in (
            self.usb_write(delayMilliseconds=5),
            self.usb_write(toleratesRejection=True),
            self.usb_write(when={"parameter": "layout", "is": ["Pro"]}),
            self.hid_write(phase="Startup"),
            self.hid_write(delayMilliseconds=5),
            self.hid_write(transport="USB"),
            self.hid_write(crc32Seed=1),
            self.hid_write(when={"parameter": "layout", "is": ["Pro"]}),
        ):
            with self.subTest(write=write):
                self.assert_rejected(
                    self.keep_alive_body(
                        "VendorGameSir",
                        {"intervalMilliseconds": 500, "writes": [write]},
                    )
                )

    def test_rejects_a_keep_alive_the_family_cannot_run(self) -> None:
        interval = {"intervalMilliseconds": 500}
        # A family that has no output at all.
        self.assert_rejected(
            self.with_body("XboxXID", defaults={"session": {"keepAlive": interval}})
        )
        # A HID write for a raw-USB family, and a raw-USB write for a HID family.
        self.assert_rejected(
            self.keep_alive_body("XboxGIP", {**interval, "writes": [self.hid_write()]})
        )
        self.assert_rejected(
            self.with_body(
                "ValveSteamDeck",
                defaults={
                    "session": {"keepAlive": {**interval, "writes": [self.usb_write()]}}
                },
            )
        )
        # A variant the family lacks (E5004) and a cadence it does not default (E5002).
        self.assert_rejected(
            self.keep_alive_body(
                "XboxGIP",
                {**interval, "writes": [self.usb_write(variants=["Wired"])]},
            ),
            code="E5004",
        )
        resend = {
            **interval,
            "writes": [self.hid_write(resendTuning="lizardResendTicks")],
        }
        self.assert_rejected(
            self.with_body(
                "ValveSteamTriton",
                tuningKeys=["lizardResendTicks"],
                defaults={"session": {"keepAlive": resend}},
            )
        )
        self.assert_rejected(
            self.with_body(
                "ValveSteamTriton",
                defaults={
                    "tuning": {"lizardResendTicks": 75},
                    "session": {"keepAlive": resend},
                },
            )
        )

    def test_rejects_the_interval_as_a_tuning_key(self) -> None:
        # The interval has one home, session.keepAlive.intervalMilliseconds. keepAliveIntervalMs
        # is no tuning key, so a description names it nowhere; each place accepts a real key.
        places = (
            lambda key: {"rawUSBTuningKeys": [key]},
            lambda key: {
                "rawUSBTuningKeys": ["usbCommandTimeoutMs"],
                "defaults": {"tuning": {key: 500}},
            },
            lambda key: {
                "rawUSBTuningKeys": ["usbCommandTimeoutMs"],
                "defaults": {"variants": {"USB": {"tuning": {key: 500}}}},
            },
        )
        for index, place in enumerate(places):
            with self.subTest(place=index):
                self.check(self.with_body("XboxGIP", **place("usbCommandTimeoutMs")))
                self.assert_rejected(
                    self.with_body("XboxGIP", **place("keepAliveIntervalMs"))
                )
        self.check(self.with_body("SonyDualSense", tuningKeys=["hidStartupIntervalMs"]))
        self.assert_rejected(
            self.with_body("SonyDualSense", tuningKeys=["keepAliveIntervalMs"])
        )

    def test_rejects_raw_usb_rules_that_contradict_each_other(self) -> None:
        for family, members in (
            ("XboxGIP", {"rawUSB": True, "tuningKeys": ["lizardResendTicks"]}),
            ("SonyDualSense", {"rawUSBTuningKeys": ["lizardResendTicks"]}),
        ):
            with self.subTest(family=family):
                self.assert_rejected(self.with_body(family, **members))

    def test_rejects_a_raw_usb_variant_the_family_does_not_have(self) -> None:
        self.assert_rejected(
            self.with_body("VendorGameSir", rawUSB=["Wired"]), code="E5004"
        )

    # Rumble templates per variant.

    def variant_rumble(self, template: dict[str, Any], **members: Any) -> Any:
        return self.with_body(
            "SonyDualSense",
            recordSections=["rumble"],
            defaults={"variants": {"USB": {"session": {"rumble": template}}}},
            **members,
        )

    def usb_rumble_template(self) -> dict[str, Any]:
        return {
            "report": {"kind": "USB", "length": 8},
            "bytes": "00 08 00 00 00 00 00 00",
            "lowFrequency": {"byte": 3, "encoding": "UInt16BigEndian"},
            "counter": {"byte": 7},
            "resendIntervalMilliseconds": 100,
        }

    def test_accepts_a_variant_rumble_template_over_the_flat_one(self) -> None:
        self.check(
            self.with_body(
                "SonyDualSense",
                recordSections=["rumble"],
                defaults={
                    "session": {"rumble": self.rumble_template()},
                    "variants": {
                        "USB": {
                            "tuning": {"stickDeadzone": 0.2},
                            "session": {
                                "rumble": {
                                    **self.rumble_template(),
                                    "lowFrequency": {"byte": 2},
                                }
                            },
                        }
                    },
                },
            )
        )
        self.check(self.variant_rumble(self.rumble_template()))
        self.check(self.variant_rumble(self.usb_rumble_template(), rawUSB=["USB"]))

    def test_rejects_a_resend_interval_in_a_family_with_a_keep_alive(self) -> None:
        template = {**self.rumble_template(), "resendIntervalMilliseconds": 100}

        def gamesir(rumble: dict[str, Any], flat: bool) -> dict[str, Any]:
            session: dict[str, Any] = {"keepAlive": {"intervalMilliseconds": 100}}
            variants: dict[str, Any] = {}
            if flat:
                session["rumble"] = rumble
            else:
                variants = {"EnhancedHID": {"session": {"rumble": rumble}}}
            return self.with_body(
                "VendorGameSir",
                rawUSB=["USB"],
                recordSections=["rumble"],
                defaults={"session": session, "variants": variants},
            )

        plain = {k: v for k, v in template.items() if k != "resendIntervalMilliseconds"}
        self.check(gamesir(plain, flat=False))
        message = "needs a family whose description declares no keepAlive"
        for name, document in (
            ("variant template", gamesir(template, flat=False)),
            ("flat template", gamesir(template, flat=True)),
        ):
            with self.subTest(name):
                self.assert_rejected(document)
                self.assertIn(
                    ("E5002", f"a rumble resendIntervalMilliseconds {message}"),
                    protocol_descriptions.semantic_violations(
                        with_variant_facts(document)
                    ),
                )

    def test_rejects_a_variant_rumble_template_the_family_cannot_use(self) -> None:
        for name, document, code in (
            (
                "driver reads no rumble section",
                self.with_body(
                    "SonyDualSense",
                    defaults={
                        "variants": {
                            "USB": {"session": {"rumble": self.rumble_template()}}
                        }
                    },
                ),
                "E5002",
            ),
            (
                "variant the family lacks",
                self.with_body(
                    "SonyDualSense",
                    recordSections=["rumble"],
                    defaults={
                        "variants": {
                            "Wired": {"session": {"rumble": self.rumble_template()}}
                        }
                    },
                ),
                "E5004",
            ),
            (
                "HID report on a raw-USB variant",
                self.variant_rumble(self.rumble_template(), rawUSB=["USB"]),
                "E5002",
            ),
            (
                "usb packet on a HID variant",
                self.variant_rumble(self.usb_rumble_template()),
                "E5002",
            ),
            (
                "bytes without the report ID",
                self.variant_rumble({**self.rumble_template(), "bytes": "02 00 00 00"}),
                "E5002",
            ),
            (
                "counter on a motor byte",
                self.variant_rumble({**self.rumble_template(), "counter": {"byte": 1}}),
                "E5002",
            ),
            (
                "member other than rumble",
                self.with_body(
                    "SonyDualSense",
                    recordSections=["rumble"],
                    defaults={
                        "variants": {"USB": {"session": {"keepAlive": {"writes": []}}}}
                    },
                ),
                "E5002",
            ),
            (
                "empty variant",
                self.with_body(
                    "SonyDualSense",
                    recordSections=["rumble"],
                    defaults={"variants": {"USB": {}}},
                ),
                "E5002",
            ),
            (
                "empty variant session",
                self.with_body(
                    "SonyDualSense",
                    recordSections=["rumble"],
                    defaults={"variants": {"USB": {"session": {}}}},
                ),
                "E5002",
            ),
        ):
            with self.subTest(name):
                self.assert_rejected(document, code=code)

    def flat_rumble(self, template: dict[str, Any], **members: Any) -> Any:
        return self.with_body(
            "SonyDualSense",
            recordSections=["rumble"],
            defaults={"session": {"rumble": template}},
            **members,
        )

    def test_checks_the_flat_rumble_template_against_each_variant_without_its_own(
        self,
    ) -> None:
        override = {"USB": {"session": {"rumble": self.usb_rumble_template()}}}
        for name, document in (
            (
                "HID template with every variant raw USB",
                self.flat_rumble(self.rumble_template(), rawUSB=True),
            ),
            (
                "usb packet with no raw-USB variant",
                self.flat_rumble(self.usb_rumble_template()),
            ),
            (
                "HID template on the raw-USB variant of a mixed family",
                self.flat_rumble(self.rumble_template(), rawUSB=["USB"]),
            ),
            (
                "usb packet on the HID variant of a mixed family",
                self.with_body(
                    "SonyDualSense",
                    recordSections=["rumble"],
                    rawUSB=["USB"],
                    defaults={
                        "session": {"rumble": self.usb_rumble_template()},
                        "variants": {
                            "BluetoothClassic": {
                                "session": {"rumble": self.usb_rumble_template()}
                            }
                        },
                    },
                ),
            ),
        ):
            with self.subTest(name):
                self.assert_rejected(document, code="E5002")
        self.check(
            self.with_body(
                "SonyDualSense",
                recordSections=["rumble"],
                rawUSB=["USB"],
                defaults={
                    "session": {"rumble": self.rumble_template()},
                    "variants": override,
                },
            )
        )
        self.check(self.flat_rumble(self.usb_rumble_template(), rawUSB=True))

    def test_xid_session_carries_only_a_usb_rumble_template(self) -> None:
        self.check(
            self.with_body(
                "XboxXID",
                defaults={"session": {"rumble": self.usb_rumble_template()}},
            )
        )
        for name, session in (
            ("HID template on a raw-USB family", {"rumble": self.rumble_template()}),
            (
                "startup beside the template",
                {
                    "rumble": self.usb_rumble_template(),
                    "startup": [{"bytes": "01 02"}],
                },
            ),
        ):
            with self.subTest(name):
                self.assert_rejected(
                    self.with_body("XboxXID", defaults={"session": session})
                )
        self.assert_rejected(
            self.with_body(
                "XboxXID",
                recordSections=["input"],
                defaults={"session": {"rumble": self.usb_rumble_template()}},
            ),
            code="E5002",
        )

    def test_session_keys_are_the_ones_the_driver_reads(self) -> None:
        usb_rumble = {"session": {"rumble": self.usb_rumble_template()}}
        self.check(self.with_body("XboxXID", defaults=usb_rumble))
        for family, keys in (
            ("XboxXID", ["keepAlive"]),
            ("XboxXID", ["startup"]),
            ("SonyDualShock4", ["keepAlive"]),
            ("SonyDualShock4", ["startup", "keepAlive"]),
            ("XboxGIP", ["startup"]),
            ("XboxXID", ["startup", "startup"]),
            ("XboxXID", ["rumble"]),
            ("XboxXID", ["subcommands"]),
            ("XboxXID", []),
        ):
            with self.subTest(family=family, keys=keys):
                self.assert_rejected(self.with_body(family, sessionKeys=keys))
        for session in (
            {"startup": [{"bytes": "01 02"}]},
            {"keepAlive": {"intervalMilliseconds": 500}},
        ):
            with self.subTest(session=session):
                self.assert_rejected(
                    self.with_body("XboxXID", defaults={"session": session})
                )

    def test_input_shape_follows_the_record_sections(self) -> None:
        usage_map = {
            "hidUsageMap": {
                "usages": [
                    {"kind": "Button", "page": 9, "usage": 1, "control": "South"}
                ]
            }
        }
        layout = {
            "report": {"length": 1},
            "buttons": [{"control": "South", "byte": 0, "mask": 1}],
        }
        self.assert_rejected(self.with_body("XboxXID", defaults={"input": usage_map}))
        self.assert_rejected(
            self.with_body("HIDReportLayout", defaults={"input": usage_map})
        )
        self.assert_rejected(
            self.with_body(
                "HIDDescriptor",
                recordSections=["hidUsageMap"],
                defaults={"input": layout},
            )
        )

    def test_rejects_tuning_keys_a_hid_family_driver_does_not_read(self) -> None:
        for family, tuning in (
            ("HIDDescriptor", {"inputLivenessTimeoutMs": 5}),
            ("HIDReportLayout", {"hidStartupRecoveryRounds": 2}),
            ("XboxXID", {"hidStartupIntervalMs": 5}),
            ("XboxXID", {"minimumHIDOutputIntervalMs": 5}),
        ):
            with self.subTest(family=family, tuning=tuning):
                self.assert_rejected(
                    self.with_body(family, defaults={"tuning": tuning})
                )

    def test_rejects_variant_defaults_the_family_does_not_have(self) -> None:
        self.assert_rejected(
            self.with_body(
                "SonyDualSense",
                tuningKeys=["hidStartupIntervalMs"],
                defaults={
                    "variants": {"Wired": {"tuning": {"hidStartupIntervalMs": 5}}}
                },
            ),
            code="E5004",
        )

    def test_rejects_variant_tuning_outside_the_variant_scope(self) -> None:
        self.assert_rejected(
            self.with_body(
                "SonyDualSense",
                tuningKeys=["hidStartupIntervalMs"],
                defaults={"variants": {"USB": {"tuning": {"usbCommandTimeoutMs": 5}}}},
            )
        )

    def test_rejects_a_variant_tuning_key_the_family_reads_only_elsewhere(self) -> None:
        self.assert_rejected(
            self.with_body(
                "SonyDualSense",
                tuningKeys=["hidStartupIntervalMs"],
                defaults={
                    "variants": {"USB": {"tuning": {"adapterDisconnectDelayMs": 5}}}
                },
            )
        )

    def test_rejects_stick_deadzone_as_a_declared_tuning_key(self) -> None:
        self.assert_rejected(
            self.with_body("SonyDualSense", tuningKeys=["stickDeadzone"])
        )
        self.assert_rejected(
            self.with_body("XboxGIP", rawUSB=True, rawUSBTuningKeys=["stickDeadzone"])
        )

    def test_rejects_a_rationale_of_the_wrong_type(self) -> None:
        for rationale in (5, None, ["rationale"], {"text": "x"}):
            with self.subTest(rationale=rationale):
                self.assert_rejected(
                    self.with_body(
                        "SonyDualSense", macOSOwnedOutput={"rationale": rationale}
                    )
                )

    def test_rejects_signatures_for_a_family_without_variants(self) -> None:
        document = self.described("HIDDescriptor", "USB")
        self.assert_rejected(document, code="E5004")

    def test_declared_parameters_are_the_vocabulary_of_the_schema(self) -> None:
        vocabulary = set(
            self.schema["properties"]["parameters"]["propertyNames"]["enum"]
        )
        declared = {
            name
            for description in protocol_descriptions.bundled().values()
            for name in description.get("parameters", {})
        }
        self.assertEqual(declared, vocabulary)

    def test_parameter_rules_name_the_family_own_variants_and_parameters(self) -> None:
        rule = {"rule": "AtMostOne", "parameters": ["maker", "role"]}
        parameters = {
            "maker": {"type": "Enum", "values": ["ThirdParty"]},
            "role": {"type": "Enum", "values": ["Receiver"]},
        }
        self.check(
            self.with_body(
                "SonyDualSense", parameters=parameters, parameterRules=[rule]
            )
        )
        self.assert_rejected(
            self.with_body(
                "SonyDualSense",
                parameters=parameters,
                parameterRules=[{**rule, "parameters": ["maker", "layout"]}],
            )
        )
        self.assert_rejected(
            self.with_body(
                "SonyDualSense",
                parameters=parameters,
                parameterRules=[{**rule, "variants": ["Wired"]}],
            ),
            code="E5004",
        )
        for malformed in (
            {"rule": "None", "parameters": ["maker"]},
            {"rule": "AtMostOne"},
            {"rule": "Sometimes", "parameters": ["maker"]},
        ):
            with self.subTest(rule=malformed):
                self.assert_rejected(
                    self.with_body(
                        "SonyDualSense",
                        parameters=parameters,
                        parameterRules=[malformed],
                    )
                )

    def test_parameters_problem_applies_each_rule(self) -> None:
        problem = protocol_descriptions.parameters_problem
        gamesir = protocol_descriptions.bundled()["VendorGameSir"]
        self.assertIsNone(problem(gamesir, "USB", {}))
        self.assertIsNotNone(problem(gamesir, "USB", {"innerGrips": True}))
        self.assertIsNotNone(problem(gamesir, "EnhancedHID", {}))
        self.assertIsNone(problem(gamesir, "EnhancedHID", {"innerGrips": True}))
        self.assertIsNotNone(
            problem(
                gamesir,
                "EnhancedHID",
                {"innerGrips": True, "lightingMemory": "ProfileSlots"},
            )
        )
        dualsense = protocol_descriptions.bundled()["SonyDualSense"]
        self.assertIsNotNone(problem(dualsense, None, {"forcedVibration": True}))
        self.assertIsNone(
            problem(dualsense, None, {"maker": "ThirdParty", "forcedVibration": True})
        )


if __name__ == "__main__":
    unittest.main()
