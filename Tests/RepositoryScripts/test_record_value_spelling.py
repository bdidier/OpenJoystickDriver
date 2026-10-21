from __future__ import annotations

import unittest
from typing import Any

from Tests.RepositoryScripts import schema_rejections
from Tests.RepositoryScripts.schema_rejections import RecordValidator
from Tests.RepositoryScripts.test_controller_schema import (
    DUALSENSE,
    GIP,
    GP100_RUMBLE,
    THIRD_PARTY,
    XUSB,
)
from Tests.RepositoryScripts.test_controller_schema import (
    record as base_record,
)


def setUpModule() -> None:
    schema_rejections.enforce_controller_rejections()


HID_REPORT = {"kind": "Output", "id": 1, "length": 4}


def mode_with_match(
    match: dict[str, Any], protocol: dict[str, Any] | None = None
) -> Any:
    return {"id": "alternative", "protocol": protocol or DUALSENSE, "match": match}


def endpoint_match(endpoint: dict[str, Any]) -> dict[str, Any]:
    return {
        "interfaceSignature": {
            "interfaceClass": 255,
            "interfaceSubclass": 71,
            "interfaceProtocol": 208,
            "endpoints": [endpoint],
        }
    }


def record(
    protocol: dict[str, Any], modes_extra: list[Any] | None = None, **fields: Any
) -> Any:
    document = base_record(protocol, **fields)
    document["modes"] = document["modes"] + (modes_extra or [])
    return document


class RecordValueSpellingTests(unittest.TestCase):
    """A value spelled as before the naming rule is an unknown name, like a random word."""

    def setUp(self) -> None:
        self.validator = RecordValidator()

    def test_the_current_spellings_are_accepted(self) -> None:
        accepted = {
            "family": record(GIP),
            "variant": record(XUSB),
            "server": record(DUALSENSE, server="OJD"),
            "rumble report kind": record(THIRD_PARTY, session={"rumble": GP100_RUMBLE}),
            "startup phase": record(
                DUALSENSE,
                session={
                    "startup": [
                        {"report": HID_REPORT, "bytes": "01 02 03", "phase": "Startup"}
                    ]
                },
            ),
        }
        for label, document in accepted.items():
            with self.subTest(label):
                self.assertTrue(self.validator.is_valid(document))

    def test_the_current_values_of_the_same_fields_are_accepted(self) -> None:
        accepted = {
            "usb configuration": record(
                GIP, usb={"configuration": "SetConfiguration1BeforeClaim"}
            ),
            "mode link": record(
                DUALSENSE, modes_extra=[mode_with_match({"link": "BluetoothClassic"})]
            ),
            "probe expectation": record(
                DUALSENSE,
                modes_extra=[
                    mode_with_match(
                        {"probes": [{"report": 239, "length": 49, "expect": "Answers"}]}
                    )
                ],
            ),
            "hat encoding": record(
                {"family": "HIDReportLayout"},
                input={
                    "report": {"length": 4},
                    "buttons": [{"control": "South", "byte": 0, "mask": 1}],
                    "hat": [{"encoding": "EightWay", "byte": 1, "mask": 15}],
                },
            ),
            "endpoint": record(
                GIP,
                modes_extra=[
                    mode_with_match(
                        endpoint_match({"direction": "In", "transferType": "Bulk"}), GIP
                    )
                ],
            ),
        }
        for label, document in accepted.items():
            with self.subTest(label):
                self.assertTrue(self.validator.is_valid(document))

    def test_unknown_names_are_rejected(self) -> None:
        old_rumble: dict[str, Any] = {
            "report": {"kind": "output", "id": 2, "length": 8},
            "lowFrequency": {"byte": 3},
        }
        rejected = {
            "family xbox.gip": record({"family": "xbox.gip"}),
            "family hid.descriptor": record({"family": "hid.descriptor"}),
            "family random word": record({"family": "banana"}),
            "variant wired": record({"family": "XboxXUSB", "variant": "wired"}),
            "variant bluetooth-le": record(
                {"family": "NintendoSwitch2", "variant": "bluetooth-le"}
            ),
            "variant enhanced-hid": record(
                {"family": "VendorGameSir", "variant": "enhanced-hid"}
            ),
            "server ojd": record(DUALSENSE, server="ojd"),
            "server system": record(DUALSENSE, server="system"),
            "report kind output": record(THIRD_PARTY, session={"rumble": old_rumble}),
            "rumble motor leftMain": record(
                THIRD_PARTY,
                session={
                    "rumble": {
                        "report": HID_REPORT,
                        "leftMain": {"byte": 3},
                    }
                },
            ),
            "startup phase startup": record(
                DUALSENSE,
                session={
                    "startup": [
                        {"report": HID_REPORT, "bytes": "01 02 03", "phase": "startup"}
                    ]
                },
            ),
            "capabilities rumble absent": record(
                DUALSENSE, capabilities={"rumble": "absent"}
            ),
            "usb configuration": record(
                GIP, usb={"configuration": "set1-before-claim"}
            ),
            "mode link": record(
                DUALSENSE, modes_extra=[mode_with_match({"link": "bluetooth-classic"})]
            ),
            "probe expectation": record(
                DUALSENSE,
                modes_extra=[
                    mode_with_match(
                        {"probes": [{"report": 239, "length": 49, "expect": "answers"}]}
                    )
                ],
            ),
            "hat encoding": record(
                {"family": "HIDReportLayout"},
                input={
                    "report": {"length": 4},
                    "buttons": [{"control": "South", "byte": 0, "mask": 1}],
                    "hat": [{"encoding": "8-way", "byte": 1, "mask": 15}],
                },
            ),
            "endpoint direction": record(
                GIP,
                modes_extra=[mode_with_match(endpoint_match({"direction": "in"}), GIP)],
            ),
            "endpoint transfer type": record(
                GIP,
                modes_extra=[
                    mode_with_match(endpoint_match({"transferType": "bulk"}), GIP)
                ],
            ),
        }
        for label, document in rejected.items():
            with self.subTest(label):
                self.assertFalse(self.validator.is_valid(document))
