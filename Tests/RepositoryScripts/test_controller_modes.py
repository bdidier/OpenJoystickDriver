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
DEFAULT = {"id": "default", "protocol": SIXAXIS}


def mode(identifier: str, *probes: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": identifier,
        "protocol": SIXAXIS,
        "match": {"probes": list(probes or [ANSWERS])},
    }


def matched(identifier: str, **keys: Any) -> dict[str, Any]:
    return {"id": identifier, "protocol": SIXAXIS, "match": keys}


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
                                "bytes": [66, 3, 0, 0],
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
                DEFAULT,
                matched(
                    "two-endpoints",
                    interfaceSignature={
                        **triple,
                        "endpoints": [
                            {"direction": "in", "transferType": "interrupt"},
                            {"direction": "out", "transferType": "interrupt"},
                        ],
                    },
                ),
                matched(
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
        self.assertNotIn("startup", generated.get("output", {}))
        self.assertEqual(
            modes["bluetooth"]["session"]["startup"][0]["bytes"], [66, 3, 0, 0]
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
            "rumble": {
                "report": {"kind": "output", "id": 2, "length": 8},
                "leftMain": {"byte": 3},
            }
        }

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
            with self.subTest(name), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "record.json"
                path.write_text(json.dumps(document))
                with self.assertRaises(validate_profiles.ValidationError) as caught:
                    validate_profiles.validate_record(path, enforce_path=False)
                self.assertIn(message, str(caught.exception))


if __name__ == "__main__":
    unittest.main()
