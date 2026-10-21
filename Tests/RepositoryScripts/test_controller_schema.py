from __future__ import annotations

import unittest
from pathlib import Path
from typing import Any

from Scripts.Catalog import validate_profiles
from Scripts.Catalog.schema_header import header
from Tests.RepositoryScripts import schema_rejections
from Tests.RepositoryScripts.schema_rejections import RecordValidator


def setUpModule() -> None:
    schema_rejections.enforce_controller_rejections()


def zeros(count: int) -> str:
    return " ".join(["00"] * count)


def record(
    protocol: dict[str, Any], session: dict[str, Any] | None = None, **fields: Any
) -> dict[str, Any]:
    mode: dict[str, Any] = {"id": "default", "protocol": protocol}
    if session is not None:
        mode["session"] = session
    return {
        **header("Controller"),
        "vendorID": 0x045E,
        "productID": 0x02EA,
        "modes": [mode],
        **fields,
    }


GIP = {"family": "XboxGIP"}
XUSB = {"family": "XboxXUSB", "variant": "Wired"}
XID = {"family": "XboxXID", "variant": "Gamepad"}
DUALSENSE = {"family": "SonyDualSense"}


def schema_clauses(node: Any) -> Any:
    """Every object nested in the schema."""
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from schema_clauses(value)
    elif isinstance(node, list):
        for value in node:
            yield from schema_clauses(value)


class ControllerSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = RecordValidator()

    def test_accepts_current_vocabulary(self) -> None:
        current = {
            "GIP parameter, actions and capabilities": record(
                {
                    **GIP,
                    "parameters": {"shareButton": {"fromEnd": 26}},
                    "initialization": ["XboxGIP/hori-ack", "XboxGIP/power-on"],
                },
                usb={"configuration": "SetConfiguration1BeforeClaim"},
                capabilities={
                    "absent": ["LeftTrigger", "RightTrigger"],
                    "rumble": "Absent",
                },
            ),
            "Joy-Con side": record(
                {"family": "NintendoSwitch1", "parameters": {"layout": "JoyConLeft"}}
            ),
            "Switch 2 Joy-Con": record(
                {"family": "NintendoSwitch2", "parameters": {"layout": "JoyConRight"}}
            ),
            "Switch 2 Pro": record({"family": "NintendoSwitch2"}),
            "Switch input-only": record({"family": "NintendoSwitchInputOnly"}),
            "Steam Triton wired": record(
                {"family": "ValveSteamTriton", "variant": "Wired"}
            ),
            "Steam Triton dongle": record(
                {"family": "ValveSteamTriton", "variant": "Dongle"}
            ),
            "Steam Triton Bluetooth LE": record(
                {"family": "ValveSteamTriton", "variant": "BluetoothLE"}
            ),
            "Steam Deck": record({"family": "ValveSteamDeck"}),
            "Switch 2 GameCube": record(
                {"family": "NintendoSwitch2", "parameters": {"layout": "GameCube"}}
            ),
            "DualSense Edge controls": record(
                DUALSENSE,
                capabilities={
                    "present": [
                        "LeftPaddle1",
                        "RightPaddle1",
                        "Auxiliary1",
                        "Auxiliary2",
                    ]
                },
            ),
            "GameSir inner grips": record(
                {
                    "family": "VendorGameSir",
                    "variant": "EnhancedHID",
                    "parameters": {"innerGrips": True},
                }
            ),
            "GameSir lighting slots": record(
                {
                    "family": "VendorGameSir",
                    "variant": "EnhancedHID",
                    "parameters": {"lightingMemory": "ProfileSlots"},
                }
            ),
            "GameSir vendor USB endpoints": record(
                {"family": "VendorGameSir", "variant": "USB"},
                usb={"endpoints": {"in": 131, "out": 3}},
            ),
            "XUSB receiver": record({"family": "XboxXUSB", "variant": "Receiver"}),
            "XID gamepad": record({"family": "XboxXID", "variant": "Gamepad"}),
            "Steam dongle": record(
                {"family": "ValveSteamController", "variant": "Dongle"}
            ),
            "descriptor HID": record({"family": "HIDDescriptor"}),
        }
        for name, document in current.items():
            with self.subTest(name):
                self.assertTrue(self.validator.is_valid(document))

    def test_rejects_a_missing_or_foreign_header(self) -> None:
        for member, value in (
            ("apiVersion", None),
            ("apiVersion", "unsupported.example/v9"),
            ("kind", None),
            ("kind", "ControllerPatch"),
        ):
            with self.subTest(member=member, value=value):
                document = record(GIP)
                if value is None:
                    del document[member]
                else:
                    document[member] = value
                self.assertFalse(self.validator.is_valid(document))
                with self.assertRaises(validate_profiles.ValidationError) as raised:
                    validate_profiles.check_record(
                        Path("record.json"), document, self.validator.schema
                    )
                self.assertEqual(
                    raised.exception.code,
                    "E5001" if member == "apiVersion" else "E5007",
                )

    def test_a_wrong_apiVersion_wins_over_other_problems(self) -> None:
        for name, document in {
            "foreign apiVersion with an unknown field": record(
                GIP, apiVersion="unsupported.example/v9", notAField="USB"
            ),
            "missing apiVersion with a foreign kind": {
                key: value
                for key, value in record(GIP, kind="ControllerPatch").items()
                if key != "apiVersion"
            },
        }.items():
            with self.subTest(name):
                with self.assertRaises(validate_profiles.ValidationError) as raised:
                    validate_profiles.check_record(
                        Path("record.json"), document, self.validator.schema
                    )
                self.assertEqual(raised.exception.code, "E5001")

    def test_rejects_unknown_vocabulary(self) -> None:
        refused = {
            "unknown field": record(GIP, notAField="USB"),
            "unknown variant": record({**GIP, "variant": "notAVariant"}),
            "unknown Steam parameter": record(
                {
                    "family": "ValveSteamController",
                    "variant": "Wired",
                    "parameters": {"notAParameter": True},
                }
            ),
            "unknown family": record({"family": "xbox.adaptive-joystick"}),
            "binding string as family": record({"family": "XboxXUSB:Wired"}),
            "missing stored variant": record({"family": "XboxXUSB"}),
            "transport variant stored": record({**DUALSENSE, "variant": "USB"}),
            "variant of another family": record(
                {"family": "XboxXUSB", "variant": "Dongle"}
            ),
            "usb block on HID family": record(
                DUALSENSE, usb={"configuration": "SetConfiguration1BeforeClaim"}
            ),
            "usb block on GameSir enhanced HID": record(
                {
                    "family": "VendorGameSir",
                    "variant": "EnhancedHID",
                    "parameters": {"innerGrips": True},
                },
                usb={"configuration": "SetConfiguration1BeforeClaim"},
            ),
            "GameSir enhanced HID without a model parameter": record(
                {"family": "VendorGameSir", "variant": "EnhancedHID"}
            ),
            "GameSir enhanced HID with both model parameters": record(
                {
                    "family": "VendorGameSir",
                    "variant": "EnhancedHID",
                    "parameters": {
                        "innerGrips": True,
                        "lightingMemory": "ProfileSlots",
                    },
                }
            ),
            "GameSir vendor USB inner grips": record(
                {
                    "family": "VendorGameSir",
                    "variant": "USB",
                    "parameters": {"innerGrips": True},
                }
            ),
            "GameSir vendor USB lighting slots": record(
                {
                    "family": "VendorGameSir",
                    "variant": "USB",
                    "parameters": {"lightingMemory": "ProfileSlots"},
                }
            ),
            "unknown parameter": record({**GIP, "parameters": {"sticksToNull": True}}),
            "wrong-family parameter": record(
                {**GIP, "parameters": {"innerGrips": True}}
            ),
            "unknown quirks array": record({**GIP, "quirks": ["share-offset"]}),
            "unknown DS4 parameter": record(
                {"family": "SonyDualShock4", "parameters": {"gyro": True}}
            ),
            "empty parameters": record({**GIP, "parameters": {}}),
            "wrong parameter type": record(
                {**GIP, "parameters": {"shareButton": {"fromEnd": "26"}}}
            ),
            "out-of-range share offset": record(
                {**GIP, "parameters": {"shareButton": {"fromEnd": 0}}}
            ),
            "unknown enum value": record(
                {"family": "NintendoSwitch1", "parameters": {"layout": "joy-con-left"}}
            ),
            "false flag": record(
                {
                    "family": "VendorGameSir",
                    "variant": "EnhancedHID",
                    "parameters": {"innerGrips": False},
                }
            ),
            "usb interface": record(GIP, usb={"interface": 1}),
            "startupPackets": record({**GIP, "startupPackets": ["XboxGIP/power-on"]}),
            "camelCase action": record({**GIP, "initialization": ["powerOn"]}),
            "XUSB initialization": record(
                {**XUSB, "initialization": ["XboxGIP/power-on"]}
            ),
            "both Joy-Con sides": record(
                {
                    "family": "NintendoSwitch1",
                    "parameters": {"layout": ["JoyConLeft", "JoyConRight"]},
                }
            ),
            "GameCube on Switch 1": record(
                {"family": "NintendoSwitch1", "parameters": {"layout": "GameCube"}}
            ),
            "Switch 2 with two layouts": record(
                {
                    "family": "NintendoSwitch2",
                    "parameters": {"layout": ["GameCube", "JoyConLeft"]},
                }
            ),
            "Switch input-only with a parameter": record(
                {
                    "family": "NintendoSwitchInputOnly",
                    "parameters": {"layout": "GameCube"},
                }
            ),
            "Steam Deck with a parameter": record(
                {"family": "ValveSteamDeck", "parameters": {"lizardMode": True}}
            ),
            "Steam Deck with a variant": record(
                {"family": "ValveSteamDeck", "variant": "Wired"}
            ),
            "Steam Triton without a variant": record({"family": "ValveSteamTriton"}),
            "Steam Triton with a parameter": record(
                {
                    "family": "ValveSteamTriton",
                    "variant": "Wired",
                    "parameters": {"lizardMode": True},
                }
            ),
            "Switch 2 with a variant": record(
                {"family": "NintendoSwitch2", "variant": "BluetoothLE"}
            ),
            "Switch 1 with an unknown parameter": record(
                {"family": "NintendoSwitch1", "parameters": {"notAParameter": True}}
            ),
            "Bluetooth-only with a layout": record(
                {
                    "family": "NintendoSwitch1",
                    "parameters": {
                        "usbProtocol": "ChargingOnly",
                        "layout": "JoyConLeft",
                    },
                }
            ),
            "XUSB rumble absence": record(XUSB, capabilities={"rumble": "Absent"}),
            "unknown control": record(GIP, capabilities={"absent": ["leftTrigger"]}),
            "empty capabilities": record(GIP, capabilities={}),
            "present on GIP": record(GIP, capabilities={"present": ["LeftPaddle1"]}),
            "partial Edge controls": record(
                DUALSENSE, capabilities={"present": ["LeftPaddle1", "Auxiliary1"]}
            ),
        }
        for protocol in (
            GIP,
            XUSB,
            {"family": "XboxXID", "variant": "Gamepad"},
            DUALSENSE,
            {"family": "ValveSteamController", "variant": "Wired"},
            {"family": "NintendoSwitch1"},
        ):
            refused[f"{protocol['family']} unknown parameter"] = record(
                {**protocol, "parameters": {"notAParameter": True}}
            )
        refused["unknown GameSir variant"] = record(
            {"family": "VendorGameSir", "variant": "notAVariant"}
        )
        for name, document in refused.items():
            with self.subTest(name):
                self.assertFalse(self.validator.is_valid(document))

    def test_rejects_protocol_default_endpoints(self) -> None:
        defaults = (
            (GIP, 130, 2),
            (XUSB, 129, 1),
            ({"family": "XboxXID", "variant": "Gamepad"}, 129, 2),
            ({"family": "VendorGameSir", "variant": "USB"}, 130, 2),
        )
        for protocol, endpoint_in, endpoint_out in defaults:
            with self.subTest(protocol["family"]):
                self.assertFalse(
                    self.validator.is_valid(
                        record(
                            protocol,
                            usb={"endpoints": {"in": endpoint_in, "out": endpoint_out}},
                        )
                    )
                )
                self.assertTrue(
                    self.validator.is_valid(
                        record(protocol, usb={"endpoints": {"in": 131, "out": 3}})
                    )
                )


THIRD_PARTY = {"family": "VendorPS3ThirdParty"}
GP100_RUMBLE = {
    "report": {"kind": "Output", "id": 2, "length": 8},
    "lowFrequency": {"byte": 3},
    "highFrequency": {"byte": 2},
}


class OwnershipAndSessionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = RecordValidator()
        self.schema_only = validate_profiles.validator()

    def test_accepts_ownership_and_rumble_template(self) -> None:
        accepted = {
            "third-party rumble": record(THIRD_PARTY, session={"rumble": GP100_RUMBLE}),
            "OJD ownership": record(THIRD_PARTY, server="OJD"),
            "macOS ownership": record(DUALSENSE, server="System"),
            "feature report": record(
                THIRD_PARTY,
                session={
                    "rumble": {
                        "report": {"kind": "Feature", "id": 0, "length": 2},
                        "rightTrigger": {"byte": 1},
                    }
                },
            ),
        }
        for name, document in accepted.items():
            with self.subTest(name):
                self.assertTrue(self.validator.is_valid(document))

    def test_accepts_template_bytes_encodings_counter_and_resend(self) -> None:
        template = {
            "report": {"kind": "Output", "id": 2, "length": 8},
            "bytes": "02 08 00 00 00 00 00 00",
            "lowFrequency": {"byte": 3, "encoding": "UInt16BigEndian"},
            "highFrequency": {"byte": 5, "encoding": "UInt16LittleEndian"},
            "counter": {"byte": 7},
            "resendIntervalMilliseconds": 100,
        }
        document = record(THIRD_PARTY, session={"rumble": template})
        self.assertTrue(self.validator.is_valid(document))
        validate_profiles.validate_modes(Path("record.json"), document)
        usb = {
            "report": {"kind": "USB", "length": 8},
            "lowFrequency": {"byte": 3, "encoding": "SwitchHDRumble"},
        }
        self.assertTrue(
            self.schema_only.is_valid(record(THIRD_PARTY, session={"rumble": usb}))
        )

    def test_rejects_a_resend_interval_that_a_keep_alive_would_retime(self) -> None:
        usb = {
            "report": {"kind": "USB", "length": 8},
            "lowFrequency": {"byte": 3},
            "resendIntervalMilliseconds": 100,
        }
        keep_alive = {"intervalMilliseconds": 500}
        refused = {
            "session keepAlive": (
                XUSB,
                {"rumble": usb, "keepAlive": keep_alive},
                "cannot be combined with a session keepAlive",
            ),
            "family keepAlive": (
                {
                    "family": "VendorGameSir",
                    "variant": "EnhancedHID",
                    "parameters": {"innerGrips": True},
                },
                {"rumble": {**GP100_RUMBLE, "resendIntervalMilliseconds": 100}},
                "needs a family whose description declares no keepAlive",
            ),
        }
        self.assertTrue(self.validator.is_valid(record(XUSB, session={"rumble": usb})))
        for name, (protocol, session, message) in refused.items():
            with self.subTest(name):
                document = record(protocol, session=session)
                self.assertFalse(self.validator.is_valid(document))
                with self.assertRaisesRegex(validate_profiles.ValidationError, message):
                    validate_profiles.validate_modes(Path("record.json"), document)

    def test_rejects_malformed_template_bytes_encodings_counter_and_resend(
        self,
    ) -> None:
        base = {
            "report": {"kind": "Output", "id": 2, "length": 8},
            "lowFrequency": {"byte": 3},
        }
        schema_rejected = {
            "unknown encoding": {
                **base,
                "lowFrequency": {"byte": 3, "encoding": "Float"},
            },
            "lowercase bytes": {**base, "bytes": "02 0a 00 00 00 00 00 00"},
            "resend of zero": {**base, "resendIntervalMilliseconds": 0},
            "usb packet with an id": {
                **base,
                "report": {"kind": "USB", "id": 2, "length": 8},
            },
            "usb packet of 65 bytes": {
                **base,
                "report": {"kind": "USB", "length": 65},
            },
        }
        semantic_rejected = {
            "bytes shorter than the report": {**base, "bytes": "02 00"},
            "bytes without the report ID": {
                **base,
                "bytes": "03 00 00 00 00 00 00 00",
            },
            "counter on a motor byte": {**base, "counter": {"byte": 3}},
            "counter on the report ID": {**base, "counter": {"byte": 0}},
            "motor wider than the report": {
                **base,
                "lowFrequency": {"byte": 7, "encoding": "UInt16BigEndian"},
            },
            "overlapping motors": {
                **base,
                "highFrequency": {"byte": 4, "encoding": "UInt16BigEndian"},
                "lowFrequency": {"byte": 3, "encoding": "UInt16BigEndian"},
            },
            "usb packet in a HID mode": {
                **base,
                "report": {"kind": "USB", "length": 8},
            },
        }
        for name, template in schema_rejected.items():
            with self.subTest(name):
                document = record(THIRD_PARTY, session={"rumble": template})
                self.assertFalse(self.validator.is_valid(document))
        for name, template in semantic_rejected.items():
            with self.subTest(name):
                document = record(THIRD_PARTY, session={"rumble": template})
                self.assertTrue(self.schema_only.is_valid(document))
                with self.assertRaises(validate_profiles.ValidationError):
                    validate_profiles.validate_modes(Path("record.json"), document)

    def test_accepts_a_rumble_template_for_each_driver_that_encodes_one(self) -> None:
        usb = {"report": {"kind": "USB", "length": 6}, "lowFrequency": {"byte": 2}}
        hid = {
            "report": {"kind": "Output", "id": 1, "length": 7},
            "lowFrequency": {"byte": 2},
        }
        accepted = {
            "XID": ({"family": "XboxXID", "variant": "Gamepad"}, usb),
            "XUSB wired": (XUSB, usb),
            "XUSB receiver": ({"family": "XboxXUSB", "variant": "Receiver"}, usb),
            "Shield 2015": (
                {
                    "family": "VendorNVIDIAShield",
                    "parameters": {"reportRevision": "Shield2015"},
                },
                hid,
            ),
            "Switch 1": (
                {"family": "NintendoSwitch1"},
                {
                    "report": {"kind": "Output", "id": 16, "length": 10},
                    "counter": {"byte": 1},
                    "lowFrequency": {"byte": 2, "encoding": "SwitchHDRumble"},
                    "highFrequency": {"byte": 6, "encoding": "SwitchHDRumble"},
                },
            ),
        }
        for name, (protocol, template) in accepted.items():
            with self.subTest(name):
                document = record(protocol, session={"rumble": template})
                self.assertTrue(self.validator.is_valid(document))
                validate_profiles.validate_modes(Path("record.json"), document)

    def test_rejects_a_rumble_template_the_driver_ignores(self) -> None:
        usb = {"report": {"kind": "USB", "length": 6}, "lowFrequency": {"byte": 2}}
        hid = {
            "report": {"kind": "Output", "id": 1, "length": 7},
            "lowFrequency": {"byte": 2},
        }
        refused = {
            "Shield without Shield2015": ({"family": "VendorNVIDIAShield"}, hid),
            "GameSir USB": ({"family": "VendorGameSir", "variant": "USB"}, usb),
        }
        for name, (protocol, template) in refused.items():
            with self.subTest(name):
                document = record(protocol, session={"rumble": template})
                with self.assertRaisesRegex(
                    validate_profiles.ValidationError,
                    "rumble templates require a driver that encodes them",
                ):
                    validate_profiles.validate_modes(Path("record.json"), document)

    def test_rejects_invalid_ownership_and_session(self) -> None:
        report = GP100_RUMBLE["report"]
        rejected = {
            "unknown ownership": record(THIRD_PARTY, server="native"),
            "GIP ownership": record(GIP, server="OJD"),
            "XUSB ownership": record(XUSB, server="System"),
            "GameSir USB ownership": record(
                {"family": "VendorGameSir", "variant": "USB"}, server="OJD"
            ),
            "template on DualSense": record(
                DUALSENSE, session={"rumble": GP100_RUMBLE}
            ),
            "keep-alive in a record": record(
                THIRD_PARTY, session={"keepAlive": {"intervalMilliseconds": 500}}
            ),
            "input report": record(
                THIRD_PARTY,
                session={
                    "rumble": {
                        "report": {**report, "kind": "input"},
                        "lowFrequency": {"byte": 3},
                    }
                },
            ),
            "no motor": record(THIRD_PARTY, session={"rumble": {"report": report}}),
            "haptic motor": record(
                THIRD_PARTY,
                session={"rumble": {"report": report, "leftHaptic": {"byte": 3}}},
            ),
            "unknown template": record(
                THIRD_PARTY, session={"rumble": GP100_RUMBLE, "lighting": {}}
            ),
            "empty session": record(THIRD_PARTY, session={}),
        }
        for name, document in rejected.items():
            with self.subTest(name):
                self.assertFalse(self.validator.is_valid(document))

    def test_route_extension_owned_applies_only_to_raw_usb_families(self) -> None:
        self.assertTrue(self.validator.is_valid(record(GIP, route="ExtensionOwned")))
        rejected = {
            "unknown route": record(GIP, route="System"),
            "DualSense route": record(DUALSENSE, route="ExtensionOwned"),
            "third-party route": record(THIRD_PARTY, route="ExtensionOwned"),
        }
        for name, document in rejected.items():
            with self.subTest(name):
                self.assertFalse(self.validator.is_valid(document))


SIXAXIS = {"family": "SonySixaxis"}
ENABLE = {
    "report": {"kind": "Feature", "id": 244, "length": 5},
    "bytes": "42 03 00 00",
    "transport": "BluetoothClassic",
}


class StartupWriteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = RecordValidator()

    def test_accepts_startup_writes(self) -> None:
        accepted = {
            "Sixaxis enable": record(SIXAXIS, session={"startup": [ENABLE]}),
            "delayed output": record(
                DUALSENSE,
                session={
                    "startup": [
                        {
                            "report": {"kind": "Output", "id": 0, "length": 2},
                            "bytes": "01 02",
                            "delayMilliseconds": 1000,
                        }
                    ]
                },
            ),
            "startup with rumble": record(
                THIRD_PARTY, session={"rumble": GP100_RUMBLE, "startup": [ENABLE]}
            ),
            "phased write": record(
                SIXAXIS, session={"startup": [{**ENABLE, "phase": "Startup"}]}
            ),
            "long report with a CRC": record(
                DS4,
                session={
                    "startup": [
                        {
                            "report": {"kind": "Output", "id": 17, "length": 78},
                            "bytes": zeros(73),
                            "crc32Seed": 162,
                        }
                    ]
                },
            ),
            "GIP packet": record(GIP, session={"startup": [USB_WRITE]}),
            "XUSB packet": record(XUSB, session={"startup": [USB_WRITE]}),
            "Switch 2 packet": record(
                {"family": "NintendoSwitch2"}, session={"startup": [USB_WRITE]}
            ),
        }
        for name, document in accepted.items():
            with self.subTest(name):
                self.assertTrue(self.validator.is_valid(document))

    def test_rejects_invalid_startup_writes(self) -> None:
        rejected = {
            "empty list": record(SIXAXIS, session={"startup": []}),
            "too many": record(SIXAXIS, session={"startup": [ENABLE] * 17}),
            "input report": record(
                SIXAXIS,
                session={
                    "startup": [
                        {**ENABLE, "report": {**ENABLE["report"], "kind": "input"}}
                    ]
                },
            ),
            "byte above 255": record(
                SIXAXIS, session={"startup": [{**ENABLE, "bytes": "100"}]}
            ),
            "no bytes": record(SIXAXIS, session={"startup": [{**ENABLE, "bytes": ""}]}),
            "long delay": record(
                SIXAXIS, session={"startup": [{**ENABLE, "delayMilliseconds": 1001}]}
            ),
            "radio transport": record(
                SIXAXIS,
                session={
                    "startup": [{**ENABLE, "transport": "ProprietaryRadioReceiver"}]
                },
            ),
            "unknown key": record(
                SIXAXIS, session={"startup": [{**ENABLE, "repeat": 2}]}
            ),
            "GIP": record(GIP, session={"startup": [ENABLE]}),
            "XUSB": record(XUSB, session={"startup": [ENABLE]}),
            "GameSir USB": record(
                {"family": "VendorGameSir", "variant": "USB"},
                session={"startup": [ENABLE]},
            ),
            "rumble on Sixaxis": record(
                SIXAXIS, session={"rumble": GP100_RUMBLE, "startup": [ENABLE]}
            ),
            "unknown phase": record(
                SIXAXIS, session={"startup": [{**ENABLE, "phase": "later"}]}
            ),
            "CRC seed above 255": record(
                SIXAXIS, session={"startup": [{**ENABLE, "crc32Seed": 256}]}
            ),
            "CRC without room": record(
                DS4,
                session={
                    "startup": [
                        {
                            "report": {"kind": "Output", "id": 1, "length": 4},
                            "bytes": "01 02 03",
                            "crc32Seed": 1,
                        }
                    ]
                },
            ),
            "report above 128 bytes": record(
                SIXAXIS,
                session={
                    "startup": [
                        {
                            **ENABLE,
                            "report": {"kind": "Output", "id": 1, "length": 129},
                        }
                    ]
                },
            ),
            "family-only variants": record(
                SIXAXIS, session={"startup": [{**ENABLE, "variants": ["USB"]}]}
            ),
            "family-only condition": record(
                SIXAXIS,
                session={
                    "startup": [{**ENABLE, "when": {"parameter": "role", "is": ["A"]}}]
                },
            ),
            "packet endpoint 0": record(
                GIP, session={"startup": [{**USB_WRITE, "endpoint": 0}]}
            ),
            "packet endpoint 128": record(
                GIP, session={"startup": [{**USB_WRITE, "endpoint": 128}]}
            ),
            "packet timeout 0": record(
                GIP, session={"startup": [{**USB_WRITE, "timeoutMilliseconds": 0}]}
            ),
            "packet timeout above 60000": record(
                GIP,
                session={"startup": [{**USB_WRITE, "timeoutMilliseconds": 60001}]},
            ),
            "packet delay above 1000": record(
                GIP, session={"startup": [{**USB_WRITE, "delayMilliseconds": 1001}]}
            ),
            "packet session byte above 63": record(
                GIP, session={"startup": [{**USB_WRITE, "sessionByte": 64}]}
            ),
            "packet above 64 bytes": record(
                GIP, session={"startup": [{**USB_WRITE, "bytes": zeros(65)}]}
            ),
            "packet with a condition": record(
                GIP,
                session={
                    "startup": [
                        {**USB_WRITE, "variants": ["USB"]},
                    ]
                },
            ),
            "packet on a HID family": record(SIXAXIS, session={"startup": [USB_WRITE]}),
            "packet on XID": record(
                {"family": "XboxXID"}, session={"startup": [USB_WRITE]}
            ),
            "packet with an initialization list": record(
                {**GIP, "initialization": ["XboxGIP/power-on"]},
                session={"startup": [USB_WRITE]},
            ),
            "packet mixed with a report": record(
                GIP, session={"startup": [USB_WRITE, ENABLE]}
            ),
        }
        for name, document in rejected.items():
            with self.subTest(name):
                self.assertFalse(self.validator.is_valid(document))


USB_WRITE = {"bytes": "05 20 00 01 00"}

REPORT_LAYOUT = {"family": "HIDReportLayout"}
BUTTON = {"control": "South", "byte": 1, "mask": 1}
LAYOUT = {"report": {"length": 2}, "buttons": [BUTTON]}


class InputLayoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = RecordValidator()

    def test_accepts_report_layouts_and_dpad_pressure(self) -> None:
        accepted = {
            "one button": record(REPORT_LAYOUT, input=LAYOUT),
            "symmetric axis without a range": record(
                REPORT_LAYOUT,
                input={
                    "report": {"length": 2},
                    "axes": [
                        {
                            "control": "LeftStickX",
                            "byte": 0,
                            "bits": 16,
                            "signed": True,
                            "symmetric": True,
                        }
                    ],
                },
            ),
            "every section": record(
                REPORT_LAYOUT,
                input={
                    "report": {"id": 1, "length": 8},
                    "buttons": [BUTTON],
                    "axes": [
                        {
                            "control": "LeftStickX",
                            "byte": 2,
                            "bits": 16,
                            "signed": True,
                            "min": -32768,
                            "max": 32767,
                            "symmetric": True,
                        },
                        {"control": "LeftStickY", "byte": 4, "inverted": True},
                    ],
                    "hat": [
                        {
                            "encoding": "EightWay",
                            "byte": 5,
                            "mask": 240,
                            "neutralUntilNonzero": True,
                        },
                        {
                            "encoding": "Directions",
                            "up": {"byte": 6, "mask": 1},
                            "right": {"byte": 6, "mask": 2},
                            "down": {"byte": 6, "mask": 4},
                            "left": {"byte": 6, "mask": 8},
                        },
                        {
                            "encoding": "Table",
                            "byte": 5,
                            "mask": 15,
                            "values": {"1": "North", "9": "NorthEast"},
                        },
                    ],
                    "leftTrigger": {"byte": 7},
                    "rightTrigger": {"button": {"byte": 1, "mask": 2}},
                },
            ),
            "layout with rumble": record(
                REPORT_LAYOUT, input=LAYOUT, session={"rumble": GP100_RUMBLE}
            ),
            "dpad pressure": record(
                {**THIRD_PARTY, "parameters": {"hatSource": "DpadPressure"}}
            ),
        }
        for name, document in accepted.items():
            with self.subTest(name):
                self.assertTrue(self.validator.is_valid(document))

    def test_rejects_invalid_report_layouts(self) -> None:
        rejected = {
            "missing input": record(REPORT_LAYOUT),
            "input on another family": record(THIRD_PARTY, input=LAYOUT),
            "report ID 0": record(
                REPORT_LAYOUT, input={**LAYOUT, "report": {"id": 0, "length": 2}}
            ),
            "long report": record(
                REPORT_LAYOUT, input={**LAYOUT, "report": {"length": 65}}
            ),
            "report only": record(REPORT_LAYOUT, input={"report": {"length": 2}}),
            "empty buttons": record(REPORT_LAYOUT, input={**LAYOUT, "buttons": []}),
            "zero mask": record(
                REPORT_LAYOUT, input={**LAYOUT, "buttons": [{**BUTTON, "mask": 0}]}
            ),
            "dpad button": record(
                REPORT_LAYOUT,
                input={**LAYOUT, "buttons": [{**BUTTON, "control": "DpadUp"}]},
            ),
            "12-bit axis": record(
                REPORT_LAYOUT,
                input={
                    **LAYOUT,
                    "axes": [{"control": "LeftStickX", "byte": 1, "bits": 12}],
                },
            ),
            "4-way hat": record(
                REPORT_LAYOUT,
                input={**LAYOUT, "hat": [{"encoding": "4-way", "byte": 1, "mask": 15}]},
            ),
            "unsigned symmetric axis": record(
                REPORT_LAYOUT,
                input={
                    **LAYOUT,
                    "axes": [{"control": "LeftStickX", "byte": 1, "symmetric": True}],
                },
            ),
            "table hat without values": record(
                REPORT_LAYOUT,
                input={
                    **LAYOUT,
                    "hat": [{"encoding": "Table", "byte": 1, "mask": 15, "values": {}}],
                },
            ),
            "table hat neutral entry": record(
                REPORT_LAYOUT,
                input={
                    **LAYOUT,
                    "hat": [
                        {
                            "encoding": "Table",
                            "byte": 1,
                            "mask": 15,
                            "values": {"0": "Neutral"},
                        }
                    ],
                },
            ),
            "empty trigger": record(REPORT_LAYOUT, input={**LAYOUT, "leftTrigger": {}}),
            "unknown section": record(REPORT_LAYOUT, input={**LAYOUT, "touchpad": {}}),
            "dpad pressure elsewhere": record(
                {**DUALSENSE, "parameters": {"hatSource": "DpadPressure"}}
            ),
        }
        for name, document in rejected.items():
            with self.subTest(name):
                self.assertFalse(self.validator.is_valid(document))


STEAM = {"family": "ValveSteamController"}
SWITCH1 = {"family": "NintendoSwitch1"}
DS4 = {"family": "SonyDualShock4"}
DUALSENSE_MODEL_PARAMETERS = (
    {"unprobedSensors": True},
    {"unprobedTouchpad": True},
    {"forcedVibration": True},
    {"role": "Receiver"},
)


class SwiftParityTests(unittest.TestCase):
    """Rules `ControllerRecordDocument` enforces, which the schema or `check_record` states."""

    def setUp(self) -> None:
        self.validator = RecordValidator()

    def check(self, accepted: dict[str, Any], rejected: dict[str, Any]) -> None:
        for name, document in accepted.items():
            with self.subTest(f"accepts {name}"):
                self.assertTrue(self.validator.is_valid(document))
        for name, document in rejected.items():
            with self.subTest(f"rejects {name}"):
                self.assertFalse(self.validator.is_valid(document))

    def test_dualsense_third_party_maker(self) -> None:
        self.check(
            {
                "maker alone": record(
                    {**DUALSENSE, "parameters": {"maker": "ThirdParty"}}
                ),
                "every model parameter": record(
                    {
                        **DUALSENSE,
                        "parameters": {
                            "maker": "ThirdParty",
                            **{
                                key: value
                                for parameter in DUALSENSE_MODEL_PARAMETERS
                                for key, value in parameter.items()
                            },
                        },
                    }
                ),
                "Sony record without parameters": record(DUALSENSE, vendorID=0x054C),
            },
            {
                f"{next(iter(parameter))} without a maker": record(
                    {**DUALSENSE, "parameters": parameter}, vendorID=0x1532
                )
                for parameter in DUALSENSE_MODEL_PARAMETERS
            },
        )

    def test_switch_layouts_are_one_value(self) -> None:
        switch2 = {"family": "NintendoSwitch2"}
        self.check(
            {
                "no parameters": record(switch2),
                **{
                    layout: record({**switch2, "parameters": {"layout": layout}})
                    for layout in ("Pro", "JoyConLeft", "JoyConRight", "GameCube")
                },
                "charging-only Switch 1": record(
                    {**SWITCH1, "parameters": {"usbProtocol": "ChargingOnly"}}
                ),
            },
            {
                f"{first} {second}": record(
                    {**switch2, "parameters": {"layout": [first, second]}}
                )
                for first, second in (
                    ("JoyConLeft", "JoyConRight"),
                    ("GameCube", "JoyConLeft"),
                    ("JoyConRight", "GameCube"),
                )
            },
        )

    def test_dualshock4_role_and_motion_scale_are_exclusive(self) -> None:
        self.check(
            {
                "factory with role": record(
                    {
                        **DS4,
                        "parameters": {
                            "motionCalibration": "Factory",
                            "role": "WirelessAdapter",
                        },
                    }
                ),
                "factory with scale": record(
                    {
                        **DS4,
                        "parameters": {
                            "motionCalibration": "Factory",
                            "motionScale": "StrikePad",
                        },
                    }
                ),
            },
            {
                "role with scale": record(
                    {
                        **DS4,
                        "parameters": {
                            "role": "WirelessAdapter",
                            "motionScale": "StrikePad",
                        },
                    }
                ),
            },
        )

    def test_steam_triton_requires_a_variant(self) -> None:
        triton = {"family": "ValveSteamTriton"}
        self.check(
            {
                f"triton {variant}": record({**triton, "variant": variant})
                for variant in ("Wired", "Dongle", "BluetoothLE")
            },
            {
                "triton without variant": record(triton),
                "triton unknown variant": record({**triton, "variant": "USB"}),
            },
        )

    def test_tuning_is_limited_to_its_families(self) -> None:
        liveness = {"inputLivenessTimeoutMs": 500}
        recovery = {"hidStartupRecoveryIntervalMs": 100, "hidStartupRecoveryRounds": 2}
        interval = {"hidStartupIntervalMs": 10}
        output = {"minimumHIDOutputIntervalMs": 8}
        unknown_key = {"notATuningKey": 500}
        self.check(
            {
                "liveness on DualShock 4": record(DS4, tuning=liveness),
                "recovery on Switch 1": record(SWITCH1, tuning=recovery),
                "recovery on a Joy-Con": record(
                    {**SWITCH1, "parameters": {"layout": "JoyConLeft"}},
                    tuning=recovery,
                ),
                "startup interval on DualSense": record(DUALSENSE, tuning=interval),
                "output interval on DualSense": record(DUALSENSE, tuning=output),
                "startup interval on GameSir enhanced HID": record(
                    {
                        "family": "VendorGameSir",
                        "variant": "EnhancedHID",
                        "parameters": {"innerGrips": True},
                    },
                    tuning=interval,
                ),
                "stick deadzone on GIP": record(GIP, tuning={"stickDeadzone": 0.1}),
                "smallest frame queue on GIP": record(
                    GIP, tuning={"frameQueueCapacity": 1}
                ),
                "largest frame queue on DualSense": record(
                    DUALSENSE, tuning={"frameQueueCapacity": 1024}
                ),
                "frame queue on XID": record(
                    {"family": "XboxXID", "variant": "Gamepad"},
                    tuning={"frameQueueCapacity": 64},
                ),
            },
            {
                # A record has no tuning key outside the schema, on any family.
                "interval on GIP": record(GIP, tuning=unknown_key),
                "interval on GameSir USB": record(
                    {"family": "VendorGameSir", "variant": "USB"}, tuning=unknown_key
                ),
                "interval on DualSense": record(DUALSENSE, tuning=unknown_key),
                "interval on XUSB": record(XUSB, tuning=unknown_key),
                "empty frame queue": record(GIP, tuning={"frameQueueCapacity": 0}),
                "oversized frame queue": record(
                    GIP, tuning={"frameQueueCapacity": 1025}
                ),
                "fractional frame queue": record(
                    GIP, tuning={"frameQueueCapacity": 1.5}
                ),
                "liveness on DualSense": record(DUALSENSE, tuning=liveness),
                "liveness on GIP": record(GIP, tuning=liveness),
                "recovery interval on DualSense": record(
                    DUALSENSE, tuning={"hidStartupRecoveryIntervalMs": 100}
                ),
                "recovery rounds on DualShock 4": record(
                    DS4, tuning={"hidStartupRecoveryRounds": 2}
                ),
                "recovery on Switch 2": record(
                    {
                        "family": "NintendoSwitch2",
                        "parameters": {"layout": "GameCube"},
                    },
                    tuning=recovery,
                ),
                "recovery on Switch input-only": record(
                    {"family": "NintendoSwitchInputOnly"}, tuning=recovery
                ),
                "startup interval on GIP": record(GIP, tuning=interval),
                "output interval on XUSB": record(XUSB, tuning=output),
                "startup interval on XID": record(
                    {"family": "XboxXID", "variant": "Gamepad"}, tuning=interval
                ),
                "output interval on GameSir USB": record(
                    {"family": "VendorGameSir", "variant": "USB"}, tuning=output
                ),
            },
        )

    def test_family_timings_are_limited_to_their_families(self) -> None:
        triton = {"family": "ValveSteamTriton", "variant": "Wired"}
        switch2 = {"family": "NintendoSwitch2"}
        gamesir = {"family": "VendorGameSir", "variant": "USB"}
        lizard = {"lizardResendTicks": 75}
        timeout = {"usbCommandTimeoutMs": 1000}
        presence = {"presenceResendReports": 4}
        disconnect = {"adapterDisconnectDelayMs": 500}
        handshake = {"usbStartupIntervalMs": 50, "usbStartupRetryDelayMs": 1000}
        transfer = {"usbTransferTimeoutMs": 2000}
        self.check(
            {
                "lizard resend on Triton": record(triton, tuning=lizard),
                "command timeout on Switch 2": record(switch2, tuning=timeout),
                "command timeout on GameSir": record(gamesir, tuning=timeout),
                "presence resend on GIP": record(GIP, tuning=presence),
                "presence resend on XUSB": record(XUSB, tuning=presence),
                "disconnect delay on DualShock 4": record(DS4, tuning=disconnect),
                "disconnect delay on DualSense": record(DUALSENSE, tuning=disconnect),
                "handshake pacing on GIP": record(GIP, tuning=handshake),
                "transfer timeout on GIP": record(GIP, tuning=transfer),
                "transfer timeout on XUSB": record(XUSB, tuning=transfer),
                "transfer timeout on XID": record(XID, tuning=transfer),
            },
            {
                "lizard resend on GIP": record(GIP, tuning=lizard),
                "command timeout on GIP": record(GIP, tuning=timeout),
                "presence resend on DualSense": record(DUALSENSE, tuning=presence),
                "disconnect delay on GIP": record(GIP, tuning=disconnect),
                "handshake pacing on XUSB": record(XUSB, tuning=handshake),
                "transfer timeout on DualSense": record(DUALSENSE, tuning=transfer),
                "transfer timeout on XUSB below range": record(
                    XUSB, tuning={"usbTransferTimeoutMs": 0}
                ),
                "transfer timeout on XUSB above range": record(
                    XUSB, tuning={"usbTransferTimeoutMs": 60001}
                ),
                "unknown tuning key on GIP": record(GIP, tuning={"zephyrQuill": 5}),
                "unknown tuning key on XUSB": record(XUSB, tuning={"zephyrQuill": 5}),
                "transfer timeout below range": record(
                    GIP, tuning={"usbTransferTimeoutMs": 0}
                ),
                "retry delay below range": record(
                    GIP, tuning={"usbStartupRetryDelayMs": 0}
                ),
                "presence resend above range": record(
                    GIP, tuning={"presenceResendReports": 1001}
                ),
            },
        )


class CapabilityOverlapTests(unittest.TestCase):
    def test_validator_rejects_overlapping_capabilities(self) -> None:
        import json
        import tempfile
        from pathlib import Path

        overlapping = record(
            DUALSENSE,
            capabilities={
                "absent": ["LeftPaddle1"],
                "present": [
                    "LeftPaddle1",
                    "RightPaddle1",
                    "Auxiliary1",
                    "Auxiliary2",
                ],
            },
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "record.json"
            path.write_text(json.dumps(overlapping))
            with self.assertRaises(validate_profiles.ValidationError):
                validate_profiles.validate_record(path, enforce_path=False)

    def test_validator_rejects_a_packet_the_description_lacks(self) -> None:
        import json
        import tempfile
        from pathlib import Path

        for action, accepted in (
            ("XboxGIP/hori-ack", True),
            ("XboxGIP/missing", False),
        ):
            with (
                self.subTest(action=action),
                tempfile.TemporaryDirectory() as directory,
            ):
                path = Path(directory) / "record.json"
                path.write_text(json.dumps(record({**GIP, "initialization": [action]})))
                if accepted:
                    validate_profiles.validate_record(path, enforce_path=False)
                else:
                    with self.assertRaises(validate_profiles.ValidationError):
                        validate_profiles.validate_record(path, enforce_path=False)


class RecordTextTests(unittest.TestCase):
    def test_refuses_text_that_is_not_utf8(self) -> None:
        import tempfile
        from pathlib import Path

        for name, data in (
            ("UTF-16", '{"apiVersion": 1}'.encode("utf-16")),
            ("Latin-1", '{"name": "caf\u00e9"}'.encode("latin-1")),
        ):
            with self.subTest(name), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "record.json"
                path.write_bytes(data)
                with self.assertRaises(validate_profiles.ValidationError) as caught:
                    validate_profiles.validate_record(path, enforce_path=False)
                self.assertEqual(caught.exception.code, "E5007")
                self.assertIn("the text is not UTF-8 (byte", str(caught.exception))

    def test_refuses_text_that_starts_with_a_utf8_byte_order_mark(self) -> None:
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "record.json"
            path.write_bytes(b"\xef\xbb\xbf" + b'{"apiVersion": 1}')
            with self.assertRaises(validate_profiles.ValidationError) as caught:
                validate_profiles.validate_record(path, enforce_path=False)
            self.assertEqual(caught.exception.code, "E5007")
            self.assertIn("UTF-8 BOM", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
