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

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


# The counts a family's description sets for its driver.
SESSION_LIMITS: dict[str, dict[str, int]] = {
    "xbox.gip": {"handshakeAttempts": 3, "announceResendLimit": 8},
    "xbox.xusb": {"receiverInquiryResendLimit": 8},
}


def xusb_description() -> dict[str, Any]:
    return {
        **header("ProtocolDescription"),
        "family": "xbox.xusb",
        "endpoints": {"in": 129, "out": 1},
        "rawUSB": True,
        "interfaceSignatures": [
            {
                "variant": "wired",
                "interfaceClass": 255,
                "interfaceSubclass": 93,
                "interfaceProtocol": 1,
            }
        ],
        "defaults": {"session": dict(SESSION_LIMITS["xbox.xusb"])},
    }


# The facts a description states about its family, which the schema ties its defaults to.
FAMILY_FACTS: dict[str, dict[str, Any]] = {
    "hid.report-layout": {"recordSections": ["input", "rumble"]},
    "xbox.gip": {"rawUSB": True},
    "xbox.xid": {"rawUSB": True, "recordSections": ["input"]},
    "xbox.xusb": {"rawUSB": True},
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
            sorted(
                family["const"]
                for rule in self.schema["allOf"]
                if (family := rule["if"].get("properties", {}).get("family"))
            ),
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
        family_delta = xusb_description()
        family_delta["defaults"] = {"capabilities": {"rumble": "absent"}}
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
        """Each family's admitted variants; the Swift tests keep these equal to `variants`."""
        families: dict[str, list[str]] = {}
        for rule in self.family_rules():
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
        document.pop("defaults")
        if family == "nintendo.switch1":
            document["defaults"] = {"session": {"subcommands": self.subcommands()}}
        elif family in SESSION_LIMITS:
            document["defaults"] = {"session": dict(SESSION_LIMITS[family])}
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

    def test_variant_lookup_fails_for_an_unknown_family(self) -> None:
        with self.assertRaisesRegex(KeyError, "xbox.unknown"):
            validate_schemas.family_variants(self.schema, "xbox.unknown")
        self.assertEqual(
            validate_schemas.family_variants(self.schema, "hid.descriptor"), []
        )
        self.assertEqual(
            validate_schemas.family_variants(self.schema, "sony.dualshock4"),
            ["usb", "bluetooth-classic"],
        )

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
        return document

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
                        "buttons": [{"control": "South", "byte": 0, "mask": 1}],
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

    def test_session_limits_belong_to_their_family(self) -> None:
        for family, limits in SESSION_LIMITS.items():
            document = self.with_body(family)
            self.check(document)
            for key in limits:
                with self.subTest(family=family, key=key, case="required"):
                    missing = self.with_body(family)
                    del missing["defaults"]["session"][key]
                    self.assert_rejected(missing)
            with self.subTest(family=family, case="no session"):
                bare = self.with_body(family)
                del bare["defaults"]
                self.assert_rejected(bare)
        for family in ("xbox.gip", "xbox.xusb", "xbox.xid", "sony.dualsense"):
            for key in (
                "handshakeAttempts",
                "announceResendLimit",
                "receiverInquiryResendLimit",
            ):
                if key in SESSION_LIMITS.get(family, {}):
                    continue
                with self.subTest(family=family, key=key, case="forbidden"):
                    document = self.with_body(family)
                    document.setdefault("defaults", {}).setdefault("session", {})[
                        key
                    ] = 3
                    self.assert_rejected(document)

    def test_session_limits_have_ranges(self) -> None:
        for family, key, low, high in (
            ("xbox.gip", "handshakeAttempts", 1, 10),
            ("xbox.gip", "announceResendLimit", 1, 100),
            ("xbox.xusb", "receiverInquiryResendLimit", 1, 100),
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
            ("hid.descriptor", {"input": input_layout}),
            ("xbox.xusb", {"input": input_layout}),
            (
                "xbox.xid",
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
            ("xbox.gip", {"unknown": {}}),
            ("xbox.gip", {"tuning": {"stickDeadzone": 5}}),
            ("xbox.gip", {"output": {"rumble": self.rumble_template()}}),
            ("xbox.xusb", {"output": {"rumble": self.rumble_template()}}),
        ):
            with self.subTest(family=family, defaults=defaults):
                self.assert_rejected(self.with_body(family, defaults=defaults))

    def rumble_template(self) -> dict[str, Any]:
        return {
            "report": {"kind": "output", "id": 1, "length": 4},
            "leftMain": {"byte": 1},
        }

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

    def usb_write(self, **members: Any) -> dict[str, Any]:
        return {"bytes": [5, 32, 0, 1, 0], **members}

    def hid_write(self, **members: Any) -> dict[str, Any]:
        return {**self.startup_write(), **members}

    def test_accepts_startup_writes_a_family_carries(self) -> None:
        for family, write in (
            (
                "xbox.gip",
                self.usb_write(endpoint=2, timeoutMilliseconds=2000, sessionByte=2),
            ),
            ("xbox.xusb", self.usb_write(delayMilliseconds=0, toleratesRejection=True)),
            ("sony.dualsense", self.hid_write(phase="startup", delayMilliseconds=5)),
            (
                "sony.dualsense",
                self.hid_write(
                    report={"kind": "output", "id": 17, "length": 78},
                    bytes=[0] * 73,
                    crc32Seed=162,
                    variants=["bluetooth-classic"],
                ),
            ),
        ):
            with self.subTest(family=family, write=write):
                self.check(
                    self.with_body(family, defaults={"output": {"startup": [write]}})
                )

    def test_rejects_malformed_startup_writes(self) -> None:
        for family, write in (
            ("xbox.gip", self.usb_write(endpoint=0)),
            ("xbox.gip", self.usb_write(endpoint=128)),
            ("xbox.gip", self.usb_write(timeoutMilliseconds=0)),
            ("xbox.gip", self.usb_write(timeoutMilliseconds=60001)),
            ("xbox.gip", self.usb_write(delayMilliseconds=1001)),
            ("xbox.gip", self.usb_write(delayMilliseconds=-1)),
            ("xbox.gip", self.usb_write(sessionByte=64)),
            ("xbox.gip", self.usb_write(bytes=[0] * 65)),
            ("xbox.gip", self.usb_write(bytes=[])),
            ("xbox.gip", self.usb_write(toleratesRejection="yes")),
            (
                "xbox.gip",
                self.usb_write(report={"kind": "output", "id": 1, "length": 4}),
            ),
            ("sony.dualsense", self.hid_write(phase="later")),
            ("sony.dualsense", self.hid_write(delayMilliseconds=1001)),
            ("sony.dualsense", self.hid_write(crc32Seed=256)),
            ("sony.dualsense", self.hid_write(crc32Seed=1)),
            (
                "sony.dualsense",
                self.hid_write(report={"kind": "output", "id": 1, "length": 129}),
            ),
            ("sony.dualsense", self.hid_write(variants=[])),
            ("sony.dualsense", self.hid_write(variants=["usb", "usb"])),
            ("sony.dualsense", self.hid_write(when={"parameter": "layout"})),
            (
                "sony.dualsense",
                self.hid_write(when={"parameter": "role", "is": ["A"], "isNot": ["B"]}),
            ),
            ("sony.dualsense", self.hid_write(when={"parameter": "role", "is": []})),
            (
                "sony.dualsense",
                self.hid_write(when={"parameter": "color", "is": ["A"]}),
            ),
        ):
            with self.subTest(family=family, write=write):
                self.assert_rejected(
                    self.with_body(family, defaults={"output": {"startup": [write]}})
                )

    def test_rejects_startup_writes_mixing_hid_and_usb_formats(self) -> None:
        self.assert_rejected(
            self.with_body(
                "sony.dualsense",
                defaults={"output": {"startup": [self.hid_write(), self.usb_write()]}},
            )
        )

    def test_rejects_hid_startup_writes_for_a_raw_usb_family(self) -> None:
        self.assert_rejected(
            self.with_body(
                "xbox.gip", defaults={"output": {"startup": [self.hid_write()]}}
            )
        )

    def test_rejects_a_startup_write_naming_what_the_family_lacks(self) -> None:
        role = {"role": {"type": "enum", "values": ["WirelessAdapter"]}}
        for write, code in (
            (self.usb_write(variants=["wired"]), "E5004"),
            (self.usb_write(when={"parameter": "layout", "is": ["Pro"]}), "E5002"),
            (self.usb_write(when={"parameter": "role", "is": ["Other"]}), "E5002"),
        ):
            with self.subTest(write=write):
                self.assert_rejected(
                    self.with_body(
                        "sony.dualshock4",
                        parameters=role,
                        defaults={"output": {"startup": [write]}},
                    ),
                    code=code,
                )

    def keep_alive_body(self, family: str, keep_alive: Any, **members: Any) -> Any:
        """A description of `family` that carries `keep_alive` in `defaults.session`."""
        keys = {
            "vendor.gamesir": {"rawUSB": ["usb"]},
            "valve.steam-triton": {"tuningKeys": ["lizardResendTicks"]},
        }
        defaults = {"session": {"keepAlive": keep_alive}}
        if family == "valve.steam-triton":
            defaults["tuning"] = {"lizardResendTicks": 75}
        return self.with_body(
            family, **keys.get(family, {}), defaults=defaults, **members
        )

    def test_accepts_keep_alives_a_family_carries(self) -> None:
        feature = {"kind": "feature", "id": 1, "length": 64}
        for family, keep_alive in (
            ("xbox.gip", {"intervalMilliseconds": 4000}),
            (
                "xbox.gip",
                {
                    "intervalMilliseconds": 1,
                    "writes": [
                        self.usb_write(endpoint=2, timeoutMilliseconds=5, sessionByte=2)
                    ],
                },
            ),
            (
                "vendor.gamesir",
                {
                    "intervalMilliseconds": 60000,
                    "writes": [
                        self.usb_write(variants=["usb"]),
                        self.hid_write(variants=["enhanced-hid"]),
                    ],
                },
            ),
            (
                "valve.steam-triton",
                {
                    "intervalMilliseconds": 40,
                    "writes": [
                        {
                            "report": feature,
                            "bytes": [0] * 63,
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
            {"intervalMilliseconds": 500, "writes": [self.usb_write(bytes=[])]},
            {"intervalMilliseconds": 500, "writes": [self.usb_write(bytes=[0] * 65)]},
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
                self.assert_rejected(self.keep_alive_body("xbox.gip", keep_alive))

    # Switch 1 subcommands.

    @staticmethod
    def spi_read(**members: Any) -> dict[str, Any]:
        return {
            "subcommand": 16,
            "spiRead": {
                "address": 24608,
                "length": 24,
                "purpose": "factoryMotionCalibration",
                **members,
            },
        }

    def subcommand_body(
        self, subcommands: Any, family: str = "nintendo.switch1"
    ) -> Any:
        return self.with_body(
            family, defaults={"session": {"subcommands": subcommands}}
        )

    @staticmethod
    def subcommands(**members: Any) -> dict[str, Any]:
        return {
            "reportId": 1,
            "counterModulus": 16,
            "requests": [{"subcommand": 3, "data": [48]}],
            **members,
        }

    def test_accepts_subcommands(self) -> None:
        plain = {"subcommand": 3, "data": [48]}
        for subcommands in (
            self.subcommands(),
            self.subcommands(counterModulus=2),
            self.subcommands(counterModulus=256),
            self.subcommands(requests=[plain] * 16),
            self.subcommands(requests=[plain, self.spi_read()]),
            self.subcommands(
                requests=[
                    self.spi_read(),
                    self.spi_read(purpose="userMotionCalibration", address=0, length=1),
                ]
            ),
            self.subcommands(requests=[self.spi_read(address=4294967295, length=29)]),
        ):
            with self.subTest(subcommands=subcommands):
                self.check(self.subcommand_body(subcommands))

    def test_rejects_malformed_subcommands(self) -> None:
        plain = {"subcommand": 3, "data": [48]}
        both = {**plain, "spiRead": self.spi_read()["spiRead"]}
        for subcommands in (
            {"counterModulus": 16, "requests": [plain]},
            {"reportId": 1, "requests": [plain]},
            {"reportId": 1, "counterModulus": 16},
            self.subcommands(reportId=256),
            self.subcommands(counterModulus=1),
            self.subcommands(counterModulus=257),
            self.subcommands(counterModulus=16.5),
            self.subcommands(requests=[]),
            self.subcommands(requests=[plain] * 17),
            self.subcommands(unknown=1),
            self.subcommands(requests=[{"subcommand": 3}]),
            self.subcommands(requests=[both]),
            self.subcommands(requests=[{"subcommand": 256, "data": [1]}]),
            self.subcommands(requests=[{"subcommand": 3, "data": []}]),
            self.subcommands(requests=[{"subcommand": 3, "data": [0] * 17}]),
            self.subcommands(requests=[{"subcommand": 3, "data": [256]}]),
            self.subcommands(requests=[{**plain, "unknown": 1}]),
            self.subcommands(requests=[self.spi_read(length=0)]),
            self.subcommands(requests=[self.spi_read(length=30)]),
            self.subcommands(requests=[self.spi_read(address=-1)]),
            self.subcommands(requests=[self.spi_read(address=4294967296)]),
            self.subcommands(requests=[self.spi_read(purpose="other")]),
            self.subcommands(requests=[self.spi_read(unknown=1)]),
            # Each purpose appears at most once.
            self.subcommands(requests=[self.spi_read(), self.spi_read(address=1)]),
        ):
            with self.subTest(subcommands=subcommands):
                self.assert_rejected(self.subcommand_body(subcommands))

    def test_only_switch_1_has_subcommands_and_it_must_have_them(self) -> None:
        self.assert_rejected(self.with_body("nintendo.switch1"))
        self.assert_rejected(
            self.with_body(
                "nintendo.switch1", defaults={"tuning": {"stickDeadzone": 0.1}}
            )
        )
        for family in ("sony.dualsense", "xbox.gip", "xbox.xid", "hid.report-layout"):
            with self.subTest(family=family):
                self.assert_rejected(self.subcommand_body(self.subcommands(), family))

    # GIP named packets.

    @staticmethod
    def named_packet(**members: Any) -> dict[str, Any]:
        return {
            "id": "xbox.gip/power-on",
            "bytes": [5, 32, 0, 1, 0],
            "sessionByte": 2,
            **members,
        }

    def named_packet_body(self, packets: Any, family: str = "xbox.gip") -> Any:
        return self.with_body(family, defaults={"session": {"namedPackets": packets}})

    def test_accepts_named_packets(self) -> None:
        for packets in (
            [self.named_packet()],
            [self.named_packet(), self.named_packet(id="xbox.gip/led-on")],
            [self.named_packet(id=f"xbox.gip/packet-{i}") for i in range(16)],
            [self.named_packet(bytes=[0, 0, 0])],
            [self.named_packet(bytes=[0] * 64)],
        ):
            with self.subTest(packets=packets):
                self.check(self.named_packet_body(packets))

    def test_rejects_malformed_named_packets(self) -> None:
        for packets in (
            [],
            [self.named_packet(id=f"xbox.gip/packet-{i}") for i in range(17)],
            [{"bytes": [5, 32, 0], "sessionByte": 2}],
            [{"id": "xbox.gip/power-on", "sessionByte": 2}],
            [{"id": "xbox.gip/power-on", "bytes": [5, 32, 0]}],
            [self.named_packet(id="power-on")],
            [self.named_packet(id="xbox.gip/Power-On")],
            [self.named_packet(id="xbox.gip/power--on")],
            [self.named_packet(id="xbox.gip/")],
            [self.named_packet(bytes=[5, 32])],
            [self.named_packet(bytes=[0] * 65)],
            [self.named_packet(bytes=[5, 32, 256])],
            [self.named_packet(sessionByte=1)],
            [self.named_packet(sessionByte=3)],
            [self.named_packet(endpoint=2)],
            [self.named_packet(unknown=1)],
            # Each id appears at most once, and starts with the family name.
            [self.named_packet(), self.named_packet(bytes=[5, 32, 0, 2])],
            [self.named_packet(id="xbox.xusb/power-on")],
        ):
            with self.subTest(packets=packets):
                self.assert_rejected(self.named_packet_body(packets))

    def test_only_gip_has_named_packets(self) -> None:
        for family in ("sony.dualsense", "xbox.xusb", "xbox.xid", "nintendo.switch2"):
            with self.subTest(family=family):
                self.assert_rejected(
                    self.named_packet_body([self.named_packet()], family)
                )

    def test_the_bundled_gip_description_names_the_eight_packets(self) -> None:
        packets = protocol_descriptions.bundled()["xbox.gip"]["defaults"]["session"][
            "namedPackets"
        ]
        self.assertEqual(
            [packet["id"] for packet in packets],
            [
                "xbox.gip/power-on",
                "xbox.gip/s-init",
                "xbox.gip/enable-extra-input",
                "xbox.gip/hori-ack",
                "xbox.gip/led-on",
                "xbox.gip/auth-done",
                "xbox.gip/rumble-begin",
                "xbox.gip/rumble-end",
            ],
        )

    def test_a_record_names_only_packets_the_description_defines(self) -> None:
        description = protocol_descriptions.bundled()["xbox.gip"]
        self.assertIsNone(
            protocol_descriptions.initialization_problem(
                description, ["xbox.gip/hori-ack", "xbox.gip/power-on"]
            )
        )
        self.assertIsNone(protocol_descriptions.initialization_problem(description, []))
        self.assertIn(
            "xbox.gip/missing",
            protocol_descriptions.initialization_problem(
                description, ["xbox.gip/power-on", "xbox.gip/missing"]
            )
            or "",
        )
        without = {
            key: value for key, value in description.items() if key != "defaults"
        }
        self.assertIsNotNone(
            protocol_descriptions.initialization_problem(without, ["xbox.gip/power-on"])
        )

    def packet_startup_body(self, startup: Any, family: str = "xbox.gip") -> Any:
        return self.with_body(
            family,
            defaults={
                "session": {"namedPackets": [self.named_packet()]},
                "output": {"startup": startup},
            },
        )

    def test_accepts_startup_that_refers_to_named_packets(self) -> None:
        for startup in (
            [{"packet": "xbox.gip/power-on"}],
            [{"packet": "xbox.gip/power-on"}, {"packet": "xbox.gip/power-on"}],
            [{"packet": "xbox.gip/power-on", "variants": ["usb"]}],
        ):
            with self.subTest(startup=startup):
                self.check(self.packet_startup_body(startup))

    def test_rejects_startup_that_refers_to_an_unknown_packet(self) -> None:
        self.assert_rejected(
            self.packet_startup_body([{"packet": "xbox.gip/missing"}]), code="E5002"
        )
        self.assert_rejected(
            self.with_body(
                "xbox.gip",
                defaults={"output": {"startup": [{"packet": "xbox.gip/power-on"}]}},
            ),
            code="E5002",
        )

    def test_rejects_malformed_or_mixed_packet_startup(self) -> None:
        for startup in (
            [{"packet": "power-on"}],
            [{"packet": "xbox.gip/power-on", "bytes": [1, 2, 3]}],
            [{"packet": "xbox.gip/power-on"}, self.usb_write()],
            [self.usb_write(), {"packet": "xbox.gip/power-on"}],
            [{"packet": "xbox.gip/power-on"}, self.hid_write()],
        ):
            with self.subTest(startup=startup):
                self.assert_rejected(self.packet_startup_body(startup))

    def test_the_bundled_gip_startup_refers_to_named_packets_only(self) -> None:
        description = protocol_descriptions.bundled()["xbox.gip"]
        self.assertEqual(
            [write["packet"] for write in description["defaults"]["output"]["startup"]],
            ["xbox.gip/power-on", "xbox.gip/led-on", "xbox.gip/auth-done"],
        )

    def test_rejects_startup_only_members_in_a_keep_alive_write(self) -> None:
        for write in (
            self.usb_write(delayMilliseconds=5),
            self.usb_write(toleratesRejection=True),
            self.usb_write(when={"parameter": "layout", "is": ["Pro"]}),
            self.hid_write(phase="startup"),
            self.hid_write(delayMilliseconds=5),
            self.hid_write(transport="usb"),
            self.hid_write(crc32Seed=1),
            self.hid_write(when={"parameter": "layout", "is": ["Pro"]}),
        ):
            with self.subTest(write=write):
                self.assert_rejected(
                    self.keep_alive_body(
                        "vendor.gamesir",
                        {"intervalMilliseconds": 500, "writes": [write]},
                    )
                )

    def test_rejects_a_keep_alive_the_family_cannot_run(self) -> None:
        interval = {"intervalMilliseconds": 500}
        # A family that has no output at all.
        self.assert_rejected(
            self.with_body("xbox.xid", defaults={"session": {"keepAlive": interval}})
        )
        # A HID write for a raw-USB family, and a raw-USB write for a HID family.
        self.assert_rejected(
            self.keep_alive_body("xbox.gip", {**interval, "writes": [self.hid_write()]})
        )
        self.assert_rejected(
            self.with_body(
                "sony.dualsense",
                defaults={
                    "session": {"keepAlive": {**interval, "writes": [self.usb_write()]}}
                },
            )
        )
        # A variant the family lacks (E5004) and a cadence it does not default (E5002).
        self.assert_rejected(
            self.keep_alive_body(
                "xbox.gip",
                {**interval, "writes": [self.usb_write(variants=["wired"])]},
            ),
            code="E5004",
        )
        resend = {
            **interval,
            "writes": [self.hid_write(resendTuning="lizardResendTicks")],
        }
        self.assert_rejected(
            self.with_body(
                "valve.steam-triton",
                tuningKeys=["lizardResendTicks"],
                defaults={"session": {"keepAlive": resend}},
            )
        )
        self.assert_rejected(
            self.with_body(
                "valve.steam-triton",
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
                "defaults": {"variants": {"usb": {"tuning": {key: 500}}}},
            },
        )
        for index, place in enumerate(places):
            with self.subTest(place=index):
                self.check(self.with_body("xbox.gip", **place("usbCommandTimeoutMs")))
                self.assert_rejected(
                    self.with_body("xbox.gip", **place("keepAliveIntervalMs"))
                )
        self.check(
            self.with_body("sony.dualsense", tuningKeys=["hidStartupIntervalMs"])
        )
        self.assert_rejected(
            self.with_body("sony.dualsense", tuningKeys=["keepAliveIntervalMs"])
        )

    def test_rejects_raw_usb_rules_that_contradict_each_other(self) -> None:
        for family, members in (
            ("xbox.gip", {"rawUSB": True, "tuningKeys": ["lizardResendTicks"]}),
            ("sony.dualsense", {"rawUSBTuningKeys": ["lizardResendTicks"]}),
        ):
            with self.subTest(family=family):
                self.assert_rejected(self.with_body(family, **members))

    def test_rejects_a_raw_usb_variant_the_family_does_not_have(self) -> None:
        self.assert_rejected(
            self.with_body("vendor.gamesir", rawUSB=["wired"]), code="E5004"
        )

    def test_rejects_variant_defaults_the_family_does_not_have(self) -> None:
        self.assert_rejected(
            self.with_body(
                "sony.dualsense",
                tuningKeys=["hidStartupIntervalMs"],
                defaults={
                    "variants": {"wired": {"tuning": {"hidStartupIntervalMs": 5}}}
                },
            ),
            code="E5004",
        )

    def test_rejects_variant_tuning_outside_the_variant_scope(self) -> None:
        self.assert_rejected(
            self.with_body(
                "sony.dualsense",
                tuningKeys=["hidStartupIntervalMs"],
                defaults={"variants": {"usb": {"tuning": {"usbCommandTimeoutMs": 5}}}},
            )
        )

    def test_rejects_a_variant_tuning_key_the_family_reads_only_elsewhere(self) -> None:
        self.assert_rejected(
            self.with_body(
                "sony.dualsense",
                tuningKeys=["hidStartupIntervalMs"],
                defaults={
                    "variants": {"usb": {"tuning": {"adapterDisconnectDelayMs": 5}}}
                },
            )
        )

    def test_rejects_stick_deadzone_as_a_declared_tuning_key(self) -> None:
        self.assert_rejected(
            self.with_body("sony.dualsense", tuningKeys=["stickDeadzone"])
        )
        self.assert_rejected(
            self.with_body("xbox.gip", rawUSB=True, rawUSBTuningKeys=["stickDeadzone"])
        )

    def test_rejects_a_rationale_of_the_wrong_type(self) -> None:
        for rationale in (5, None, ["rationale"], {"text": "x"}):
            with self.subTest(rationale=rationale):
                self.assert_rejected(
                    self.with_body(
                        "sony.dualsense", macOSOwnedOutput={"rationale": rationale}
                    )
                )

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
        for rule in self.family_rules():
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
