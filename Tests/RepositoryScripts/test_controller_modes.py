from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any, ClassVar

from Scripts.Catalog import validate_profiles
from Scripts.Catalog.schema_header import header

SIXAXIS = {"family": "sony.sixaxis"}
ANSWERS = {"report": 239, "length": 64, "expect": "answers"}
DEFAULT = {"id": "default", "protocol": SIXAXIS}


def mode(identifier: str, *probes: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": identifier,
        "protocol": SIXAXIS,
        "match": {"probes": list(probes or [ANSWERS])},
    }


def matched(identifier: str, **keys: Any) -> dict[str, Any]:
    return {"id": identifier, "protocol": SIXAXIS, "match": keys}


GIP = {"family": "xbox.gip"}
GIP_DEFAULT = {"id": "default", "protocol": GIP}


def gip_matched(identifier: str, **keys: Any) -> dict[str, Any]:
    return {"id": identifier, "protocol": GIP, "match": keys}


def record(**fields: Any) -> dict[str, Any]:
    return {
        **header("Controller"),
        "vendorID": 0x054C,
        "productID": 0x0268,
        "modes": [DEFAULT],
        **fields,
    }


class ControllerModeSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = validate_profiles.validator()

    def test_accepts_modes_selected_by_each_probe_expectation(self) -> None:
        document = record(
            modes=[
                DEFAULT,
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

    def test_accepts_modes_selected_by_cheap_keys(self) -> None:
        wired = {"link": "usb", "bcdDevice": {"min": 0, "max": 255}}
        document = record(
            modes=[
                DEFAULT,
                matched("bluetooth", link="bluetooth-classic"),
                matched("dongle", link="proprietary-radio-receiver"),
                matched("wired", **wired),
                matched(
                    "named",
                    manufacturer="Sony",
                    product="PLAYSTATION(R)3 Controller",
                    interfaceSignature={
                        "interfaceClass": 3,
                        "interfaceSubclass": 0,
                        "interfaceProtocol": 0,
                        "usagePage": 1,
                        "usage": 5,
                    },
                    probes=[ANSWERS],
                ),
                {
                    **matched("ranged", link="usb"),
                    "interface": {"first": 1, "last": 2},
                    "session": {
                        "startup": [
                            {
                                "report": {"kind": "feature", "id": 244, "length": 5},
                                "bytes": "42 03 00 00",
                            }
                        ]
                    },
                },
            ]
        )
        self.assertTrue(self.validator.is_valid(document))

    def test_accepts_modes_told_apart_by_endpoint_set(self) -> None:
        triple = {
            "interfaceClass": 255,
            "interfaceSubclass": 93,
            "interfaceProtocol": 1,
        }
        document = record(
            modes=[
                GIP_DEFAULT,
                gip_matched(
                    "two-endpoints",
                    interfaceSignature={
                        **triple,
                        "endpoints": [
                            {"direction": "in", "transferType": "interrupt"},
                            {"direction": "out", "transferType": "interrupt"},
                        ],
                    },
                ),
                gip_matched(
                    "one-endpoint",
                    interfaceSignature={
                        **triple,
                        "endpoints": [
                            {
                                "address": 129,
                                "direction": "in",
                                "transferType": "bulk",
                                "maxPacketSize": 64,
                            }
                        ],
                    },
                ),
            ]
        )
        self.assertTrue(self.validator.is_valid(document))

    def test_ds3_record_holds_bluetooth_as_a_link_mode(self) -> None:
        generated = json.loads(
            (
                Path(__file__).resolve().parents[2]
                / "Sources/OpenJoystickDriverKit/Resources/Controllers/054c/054c-0268.json"
            ).read_text()
        )
        self.assertTrue(self.validator.is_valid(generated))
        modes = {entry["id"]: entry for entry in generated["modes"]}
        self.assertEqual(modes["bluetooth"]["match"], {"link": "bluetooth-classic"})
        self.assertEqual(
            modes["bluetooth"]["session"]["startup"][0]["bytes"], "42 03 00 00"
        )

    def test_rejects_invalid_modes(self) -> None:
        bytes_probe = {"report": 1, "length": 8, "expect": "bytes"}

        def with_endpoints(endpoints: list[dict[str, Any]]) -> dict[str, Any]:
            return {
                "interfaceClass": 255,
                "interfaceSubclass": 93,
                "interfaceProtocol": 1,
                "endpoints": endpoints,
            }

        rejected = {
            "empty modes": record(modes=[]),
            "no default mode": record(modes=[mode("x")]),
            "two default modes": record(modes=[DEFAULT, DEFAULT]),
            "default with a match": record(
                modes=[{**DEFAULT, "match": {"link": "usb"}}]
            ),
            "uppercase id": record(modes=[DEFAULT, mode("XInput")]),
            "id with a trailing newline": record(modes=[DEFAULT, mode("abc\n")]),
            "bytes with a trailing newline": record(
                modes=[
                    DEFAULT,
                    mode("x", {**bytes_probe, "offset": 0, "bytes": "AB\n"}),
                ]
            ),
            "no probes": record(modes=[DEFAULT, matched("x", probes=[])]),
            "no match": record(modes=[DEFAULT, {"id": "x", "protocol": SIXAXIS}]),
            "empty match": record(modes=[DEFAULT, {**mode("x"), "match": {}}]),
            "unknown link": record(modes=[DEFAULT, matched("x", link="serial")]),
            "bcdDevice above 16 bits": record(
                modes=[DEFAULT, matched("x", bcdDevice={"min": 0, "max": 65536})]
            ),
            "empty manufacturer": record(
                modes=[DEFAULT, matched("x", manufacturer="")]
            ),
            "signature without a class": record(
                modes=[
                    DEFAULT,
                    matched("x", interfaceSignature={"interfaceSubclass": 1}),
                ]
            ),
            "endpoints without an entry": record(
                modes=[
                    DEFAULT,
                    matched("x", interfaceSignature=with_endpoints([])),
                ]
            ),
            "endpoint without a key": record(
                modes=[
                    DEFAULT,
                    matched("x", interfaceSignature=with_endpoints([{}])),
                ]
            ),
            "endpoint with a bad direction": record(
                modes=[
                    DEFAULT,
                    matched(
                        "x", interfaceSignature=with_endpoints([{"direction": "both"}])
                    ),
                ]
            ),
            "endpoint with a bad transfer type": record(
                modes=[
                    DEFAULT,
                    matched(
                        "x",
                        interfaceSignature=with_endpoints(
                            [{"transferType": "unknown"}]
                        ),
                    ),
                ]
            ),
            "endpoint address above 255": record(
                modes=[
                    DEFAULT,
                    matched("x", interfaceSignature=with_endpoints([{"address": 256}])),
                ]
            ),
            "endpoint packet size above 16 bits": record(
                modes=[
                    DEFAULT,
                    matched(
                        "x",
                        interfaceSignature=with_endpoints([{"maxPacketSize": 65536}]),
                    ),
                ]
            ),
            "endpoint with an unknown key": record(
                modes=[
                    DEFAULT,
                    matched("x", interfaceSignature=with_endpoints([{"interval": 1}])),
                ]
            ),
            "endpoints on a HID mode": record(
                modes=[
                    DEFAULT,
                    matched(
                        "x",
                        interfaceSignature=with_endpoints(
                            [{"direction": "in", "transferType": "interrupt"}]
                        ),
                    ),
                ]
            ),
            "session with an empty startup": record(
                modes=[
                    DEFAULT,
                    {**matched("x", link="usb"), "session": {"startup": []}},
                ]
            ),
            "unknown mode key": record(
                modes=[DEFAULT, {**matched("x", link="usb"), "keepAlive": 1}]
            ),
            "unknown match key": record(
                modes=[
                    DEFAULT,
                    matched("x", probes=[ANSWERS], serialNumber="1"),
                ]
            ),
            "write probe": record(
                modes=[DEFAULT, mode("x", {**ANSWERS, "write": "01"})]
            ),
            "unknown expectation": record(
                modes=[DEFAULT, mode("x", {**ANSWERS, "expect": "a"})]
            ),
            "bytes without pattern": record(modes=[DEFAULT, mode("x", bytes_probe)]),
            "pattern on answers": record(
                modes=[DEFAULT, mode("x", {**ANSWERS, "offset": 0, "bytes": "01"})]
            ),
            "lowercase hex": record(
                modes=[DEFAULT, mode("x", {**bytes_probe, "offset": 0, "bytes": "ab"})]
            ),
            "unpaired hex": record(
                modes=[DEFAULT, mode("x", {**bytes_probe, "offset": 0, "bytes": "A"})]
            ),
            "report above 255": record(
                modes=[DEFAULT, mode("x", {**ANSWERS, "report": 256})]
            ),
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
            "duplicate id": record(modes=[DEFAULT, mode("a"), mode("a")]),
            "no default mode": record(modes=[mode("a")]),
            "two default modes": record(modes=[DEFAULT, DEFAULT]),
            "default with a match": record(
                modes=[{**DEFAULT, "match": {"link": "usb"}}]
            ),
            "bcdDevice min above max": record(
                modes=[DEFAULT, matched("x", bcdDevice={"min": 5, "max": 4})]
            ),
            "interface first above last": record(
                modes=[
                    DEFAULT,
                    {**matched("x", link="usb"), "interface": {"first": 2, "last": 1}},
                ]
            ),
            "bytes past length": record(modes=[DEFAULT, mode("a", overflowing)]),
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
            "report": {"kind": "output", "id": 2, "length": 8},
            "leftMain": {"byte": 3},
        }

        def with_session_mode(
            family: str, default: str, session: dict[str, Any]
        ) -> dict[str, Any]:
            document = with_mode(family, default)
            document["modes"][1]["session"] = session
            return document

        def with_mode(family: str, default: str, **fields: Any) -> dict[str, Any]:
            return {
                **record(**fields),
                "modes": [
                    {"id": "default", "protocol": {"family": default}},
                    {
                        "id": "x",
                        "protocol": {"family": family},
                        "match": {"probes": [ANSWERS]},
                    },
                ],
            }

        needs_layout = "every mode needs the record's input layout exactly when it is hid.report-layout"
        rejected = {
            "input layout on a mode that is not hid.report-layout": (
                with_mode("sony.sixaxis", "hid.report-layout", input=layout),
                needs_layout,
            ),
            "hid.report-layout mode without the input layout": (
                with_mode("hid.report-layout", "sony.sixaxis"),
                needs_layout,
            ),
            "rumble template on a mode whose driver does not encode it": (
                with_session_mode(
                    "hid.descriptor", "vendor.ps3-third-party", {"rumble": rumble}
                ),
                "rumble templates require a driver that encodes them",
            ),
            "present controls on a mode whose driver does not declare them": (
                with_mode(
                    "sony.sixaxis",
                    "sony.dualsense",
                    capabilities={
                        "present": sorted(
                            validate_profiles.description_of("sony.dualsense")[
                                "recordCapabilities"
                            ]["present"]
                        )
                    },
                ),
                "capabilities must be deltas the driver of every mode declares",
            ),
        }
        for name, (document, message) in rejected.items():
            with self.subTest(name):
                with self.assertRaises(validate_profiles.ValidationError) as caught:
                    validate_profiles.validate_modes(Path("record.json"), document)
                self.assertIn(message, str(caught.exception))

    def test_single_mode_records_get_the_same_per_mode_checks(self) -> None:
        layout = {
            "report": {"length": 8},
            "buttons": [{"control": "South", "byte": 0, "mask": 1}],
        }
        rumble = {
            "report": {"kind": "output", "id": 2, "length": 8},
            "leftMain": {"byte": 3},
        }

        def single(
            family: str, session: dict[str, Any] | None = None, **fields: Any
        ) -> dict[str, Any]:
            default: dict[str, Any] = {"id": "default", "protocol": {"family": family}}
            if session is not None:
                default["session"] = session
            return record(modes=[default], **fields)

        schema = validate_profiles.validator()
        rejected = {
            "report-layout without a layout": single("hid.report-layout"),
            "layout under another family": single("sony.sixaxis", input=layout),
            "template under hid.descriptor": single(
                "hid.descriptor", {"rumble": rumble}
            ),
            "template under a raw-USB family": single("xbox.gip", {"rumble": rumble}),
        }
        for name, document in rejected.items():
            with self.subTest(name):
                self.assertFalse(schema.is_valid(document))
                with self.assertRaises(validate_profiles.ValidationError):
                    validate_profiles.validate_modes(Path("record.json"), document)
        for name, document in {
            "layout": single("hid.report-layout", input=layout),
            "layout and template": single(
                "hid.report-layout", {"rumble": rumble}, input=layout
            ),
        }.items():
            with self.subTest(name):
                self.assertTrue(schema.is_valid(document))
                validate_profiles.validate_modes(Path("record.json"), document)


class RawUSBModeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.schema = validate_profiles.validator()

    @staticmethod
    def gip(identifier: str = "default", **fields: Any) -> dict[str, Any]:
        return {"id": identifier, "protocol": {"family": "xbox.gip"}, **fields}

    def usb_record(self, *modes: dict[str, Any]) -> dict[str, Any]:
        return record(modes=list(modes))

    def test_accepts_alternative_modes_and_usb_sessions_on_raw_usb(self) -> None:
        usb_write = {"bytes": "01 02"}
        document = self.usb_record(
            self.gip(),
            self.gip("alt", match={"link": "usb"}, session={"startup": [usb_write]}),
        )
        self.assertTrue(self.schema.is_valid(document))
        validate_profiles.validate_modes(Path("record.json"), document)

    def test_endpoints_are_accepted_on_raw_usb_and_refused_on_hid(self) -> None:
        signature = {
            "interfaceClass": 255,
            "interfaceSubclass": 71,
            "interfaceProtocol": 208,
            "endpoints": [{"direction": "in", "transferType": "interrupt"}],
        }
        accepted = self.usb_record(
            self.gip(), self.gip("a", match={"interfaceSignature": signature})
        )
        self.assertTrue(self.schema.is_valid(accepted))
        validate_profiles.validate_modes(Path("record.json"), accepted)
        refused = record(modes=[DEFAULT, matched("a", interfaceSignature=signature)])
        self.assertFalse(self.schema.is_valid(refused))
        with self.assertRaises(validate_profiles.ValidationError) as caught:
            validate_profiles.validate_modes(Path("record.json"), refused)
        self.assertIn("HID mode", str(caught.exception))

    def test_rejects_what_a_raw_usb_mode_cannot_carry(self) -> None:
        hid_write = {
            "report": {"kind": "feature", "id": 1, "length": 2},
            "bytes": "01 02",
        }
        usb_write = {"bytes": "01 02"}
        rejected = {
            "interface on raw USB": (
                self.usb_record(
                    self.gip(),
                    self.gip(
                        "a", match={"link": "usb"}, interface={"first": 0, "last": 1}
                    ),
                ),
                "interface selects among HID interfaces",
                False,
            ),
            "HID session on raw USB": (
                self.usb_record(
                    self.gip(),
                    self.gip(
                        "a", match={"link": "usb"}, session={"startup": [hid_write]}
                    ),
                ),
                "",
                False,
            ),
            "USB packets in a HID mode": (
                self.usb_record({**DEFAULT, "session": {"startup": [usb_write]}}),
                "",
                False,
            ),
            "session naming both kinds": (
                self.usb_record(self.gip(session={"startup": [hid_write, usb_write]})),
                "",
                False,
            ),
            "session naming nothing": (
                self.usb_record(self.gip(session={})),
                "",
                False,
            ),
        }
        for name, (document, message, schema_accepts) in rejected.items():
            with self.subTest(name):
                self.assertEqual(self.schema.is_valid(document), schema_accepts)
                if message:
                    with self.assertRaises(validate_profiles.ValidationError) as caught:
                        validate_profiles.validate_modes(Path("record.json"), document)
                    self.assertIn(message, str(caught.exception))


class SessionTests(unittest.TestCase):
    """One session shape serves every mode; its keys follow the mode's own protocol."""

    SHANWAN: ClassVar[dict[str, Any]] = {"manufacturer": "SHANWAN"}

    def setUp(self) -> None:
        self.schema = validate_profiles.validator()

    @staticmethod
    def read(request: int, **fields: Any) -> dict[str, Any]:
        return {
            "bmRequestType": 192,
            "bRequest": request,
            "wValue": 0,
            "wIndex": 0,
            "wLength": 8,
            **fields,
        }

    def document(self, family: str, session: dict[str, Any]) -> dict[str, Any]:
        protocol = {"family": family}
        if family == "xbox.xusb":
            protocol["variant"] = "wired"
        return record(
            modes=[{"id": "default", "protocol": protocol, "session": session}]
        )

    def reads(self) -> list[dict[str, Any]]:
        return [self.read(n, match=self.SHANWAN) for n in (1, 2, 3)]

    def test_gated_vendor_reads_are_accepted_on_a_raw_usb_mode(self) -> None:
        document = self.document("xbox.xusb", {"control": self.reads()})
        self.assertTrue(self.schema.is_valid(document))
        validate_profiles.validate_modes(Path("record.json"), document)
        gates = [t["match"] for t in document["modes"][0]["session"]["control"]]
        self.assertEqual(gates, [self.SHANWAN] * 3)

    def test_byte_format_is_uppercase_hex_pairs_with_single_spaces(self) -> None:
        for text in ("0x1a 2b", "1a 2b", "1A  2B", "1A2B", " 1A", "1A ", "1A\n", ""):
            with self.subTest(text):
                document = self.document("xbox.xusb", {"startup": [{"bytes": text}]})
                self.assertFalse(self.schema.is_valid(document))
        accepted = self.document("xbox.xusb", {"startup": [{"bytes": "1A 2B"}]})
        self.assertTrue(self.schema.is_valid(accepted))

    def test_rejects_sessions_a_mode_cannot_run(self) -> None:
        write = {"bytes": "01 02"}
        rejected = {
            "control on a HID mode": ("sony.sixaxis", {"control": self.reads()}),
            "settle on a HID mode": ("sony.sixaxis", {"settleMilliseconds": 200}),
            "shutdown on a HID mode": ("sony.sixaxis", {"shutdown": [write]}),
            "keep-alive on a HID mode": (
                "sony.sixaxis",
                {"keepAlive": {"intervalMilliseconds": 100, "writes": [write]}},
            ),
            "keep-alive on a family that declares one": (
                "xbox.gip",
                {"keepAlive": {"intervalMilliseconds": 100, "writes": [write]}},
            ),
        }
        for name, (family, session) in rejected.items():
            with self.subTest(name):
                self.assertFalse(self.schema.is_valid(self.document(family, session)))

    def test_validator_rejects_control_transfers_that_disagree_with_themselves(
        self,
    ) -> None:
        out = {
            "bmRequestType": 64,
            "bRequest": 1,
            "wValue": 0,
            "wIndex": 0,
            "wLength": 3,
            "data": "01 02",
        }
        inverted = self.read(1, match={"bcdDevice": {"min": 5, "max": 4}})
        rejected = {
            "data count differs from wLength": (
                out,
                "control transfer data has 2 bytes, but wLength is 3",
            ),
            "bcdDevice min above max": (
                inverted,
                "control transfer bcdDevice min must not exceed max",
            ),
        }
        for name, (transfer, message) in rejected.items():
            with self.subTest(name):
                document = self.document("xbox.xusb", {"control": [transfer]})
                self.assertTrue(self.schema.is_valid(document))
                with self.assertRaises(validate_profiles.ValidationError) as caught:
                    validate_profiles.validate_modes(Path("record.json"), document)
                self.assertIn(message, str(caught.exception))

    def test_accepts_settle_shutdown_and_keep_alive_on_raw_usb(self) -> None:
        write = {"bytes": "01 02"}
        document = self.document(
            "xbox.xusb",
            {
                "settleMilliseconds": 200,
                "shutdown": [write],
                "keepAlive": {"intervalMilliseconds": 100, "writes": [write]},
            },
        )
        self.assertTrue(self.schema.is_valid(document))
        validate_profiles.validate_modes(Path("record.json"), document)


class EveryModeConditionalTests(unittest.TestCase):
    """A record-level section that depends on a mode's protocol holds for every mode: the
    default mode satisfies each rule here and a second mode breaks it."""

    HID: ClassVar[dict[str, Any]] = {"family": "sony.sixaxis"}
    GIP: ClassVar[dict[str, Any]] = {"family": "xbox.gip"}
    HID_MATCH: ClassVar[dict[str, Any]] = {"probes": [ANSWERS]}
    USB_MATCH: ClassVar[dict[str, Any]] = {"link": "usb"}

    def second_mode(
        self,
        default: dict[str, Any],
        second: dict[str, Any],
        match: dict[str, Any],
        **fields: Any,
    ) -> dict[str, Any]:
        return record(
            modes=[
                {"id": "default", "protocol": default},
                {"id": "second", "protocol": second, "match": match},
            ],
            **fields,
        )

    def assert_rejected(self, document: dict[str, Any], message: str) -> None:
        self.assertFalse(validate_profiles.validator().is_valid(document))
        with self.assertRaises(validate_profiles.ValidationError) as caught:
            validate_profiles.validate_modes(Path("record.json"), document)
        self.assertIn(message, str(caught.exception))

    def test_usb_needs_every_mode_raw_usb(self) -> None:
        self.assert_rejected(
            self.second_mode(
                self.GIP,
                self.HID,
                self.HID_MATCH,
                usb={"configuration": "set1-before-claim"},
            ),
            "USB overrides require a raw-USB protocol family",
        )

    def test_server_needs_every_mode_hid(self) -> None:
        self.assert_rejected(
            self.second_mode(self.HID, self.GIP, self.USB_MATCH, server="ojd"),
            "server applies only to HID controllers",
        )

    def test_route_needs_every_mode_raw_usb(self) -> None:
        self.assert_rejected(
            self.second_mode(
                self.GIP, self.HID, self.HID_MATCH, route="ExtensionOwned"
            ),
            "route ExtensionOwned applies only to raw-USB controllers",
        )

    def test_session_follows_the_protocol_of_its_own_mode(self) -> None:
        document = self.second_mode(self.GIP, self.HID, self.HID_MATCH)
        document["modes"][1]["session"] = {"settleMilliseconds": 200}
        self.assert_rejected(
            document, "session settleMilliseconds applies only to raw-USB modes"
        )

    def test_tuning_keys_are_read_by_every_mode(self) -> None:
        self.assert_rejected(
            self.second_mode(
                {"family": "sony.dualshock4"},
                self.HID,
                self.HID_MATCH,
                tuning={"inputLivenessTimeoutMs": 500},
            ),
            "inputLivenessTimeoutMs is not read by the sony.sixaxis driver",
        )

    def test_bluetooth_le_needs_every_mode_switch_2(self) -> None:
        self.assert_rejected(
            self.second_mode(
                {"family": "nintendo.switch2"},
                self.HID,
                self.HID_MATCH,
                bluetoothLE={
                    "vibrationCharacteristic": "00000000-0000-0000-0000-000000000000"
                },
            ),
            "bluetoothLE requires a Switch 2 controller",
        )

    def test_usb_endpoints_differ_from_every_mode_default(self) -> None:
        self.assert_rejected(
            self.second_mode(
                self.GIP,
                {"family": "xbox.xusb", "variant": "wired"},
                self.USB_MATCH,
                usb={"endpoints": {"in": 129, "out": 1}},
            ),
            "protocol-default endpoints must be omitted",
        )

    def test_hid_usage_map_needs_every_mode_hid_descriptor(self) -> None:
        self.assert_rejected(
            self.second_mode(
                {"family": "hid.descriptor"},
                self.HID,
                self.HID_MATCH,
                input={
                    "hidUsageMap": {
                        "usages": [
                            {
                                "kind": "button",
                                "page": 9,
                                "usage": 1,
                                "control": "South",
                            }
                        ]
                    }
                },
            ),
            "a HID usage map applies only to hid.descriptor in every mode",
        )


if __name__ == "__main__":
    unittest.main()
