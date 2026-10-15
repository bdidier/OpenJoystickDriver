from __future__ import annotations

import unittest
from typing import Any

from Scripts.Catalog import validate_profiles
from Scripts.Catalog.schema_header import header


def record(protocol: dict[str, Any], **fields: Any) -> dict[str, Any]:
    return {
        **header("Controller"),
        "vendorID": 0x045E,
        "productID": 0x02EA,
        "protocol": protocol,
        **fields,
    }


GIP = {"family": "xbox.gip"}
XUSB = {"family": "xbox.xusb", "variant": "wired"}
DUALSENSE = {"family": "sony.dualsense"}


class ControllerSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = validate_profiles.validator()

    def test_accepts_current_vocabulary(self) -> None:
        current = {
            "GIP parameter, actions and capabilities": record(
                {
                    **GIP,
                    "parameters": {"shareButton": {"fromEnd": 26}},
                    "initialization": ["xbox.gip/hori-ack", "xbox.gip/power-on"],
                },
                usb={"configuration": "set1-before-claim"},
                capabilities={
                    "absent": ["left-trigger", "right-trigger"],
                    "rumble": "absent",
                },
            ),
            "Joy-Con side": record(
                {"family": "nintendo.switch1", "parameters": {"layout": "JoyConLeft"}}
            ),
            "Switch 2 Joy-Con": record(
                {"family": "nintendo.switch2", "parameters": {"layout": "JoyConRight"}}
            ),
            "Switch 2 Pro": record({"family": "nintendo.switch2"}),
            "Switch input-only": record({"family": "nintendo.switch-input-only"}),
            "Steam Triton wired": record(
                {"family": "valve.steam-triton", "variant": "wired"}
            ),
            "Steam Triton dongle": record(
                {"family": "valve.steam-triton", "variant": "dongle"}
            ),
            "Steam Triton Bluetooth LE": record(
                {"family": "valve.steam-triton", "variant": "bluetooth-le"}
            ),
            "Steam Deck": record({"family": "valve.steam-deck"}),
            "Switch 2 GameCube": record(
                {"family": "nintendo.switch2", "parameters": {"layout": "GameCube"}}
            ),
            "DualSense Edge controls": record(
                DUALSENSE,
                capabilities={
                    "present": [
                        "paddle-left-1",
                        "paddle-right-1",
                        "auxiliary-1",
                        "auxiliary-2",
                    ]
                },
            ),
            "GameSir inner grips": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "enhanced-hid",
                    "parameters": {"innerGrips": True},
                }
            ),
            "GameSir lighting slots": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "enhanced-hid",
                    "parameters": {"lightingMemory": "ProfileSlots"},
                }
            ),
            "GameSir vendor USB endpoints": record(
                {"family": "vendor.gamesir", "variant": "usb"},
                usb={"endpoints": {"in": 131, "out": 3}},
            ),
            "XUSB receiver": record({"family": "xbox.xusb", "variant": "receiver"}),
            "XID gamepad": record({"family": "xbox.xid", "variant": "gamepad"}),
            "Steam dongle": record(
                {"family": "valve.steam-controller", "variant": "dongle"}
            ),
            "descriptor HID": record({"family": "hid.descriptor"}),
        }
        for name, document in current.items():
            with self.subTest(name):
                self.assertTrue(self.validator.is_valid(document))

    def test_rejects_removed_vocabulary(self) -> None:
        removed = {
            "legacy driver": record({"driver": "GIP", "variant": "xboxOne"}),
            "legacy variant": record({**GIP, "variant": "xboxOne"}),
            "legacy XUSB variant": record(
                {"family": "xbox.xusb", "variant": "xbox360"}
            ),
            "transport field": record(GIP, transport="usb"),
            "Steam wirelessReceiver parameter": record(
                {
                    "family": "valve.steam-controller",
                    "variant": "wired",
                    "parameters": {"wirelessReceiver": True},
                }
            ),
            "unknown family": record({"family": "xbox.adaptive-joystick"}),
            "binding string as family": record({"family": "xbox.xusb:wired"}),
            "missing stored variant": record({"family": "xbox.xusb"}),
            "transport variant stored": record({**DUALSENSE, "variant": "usb"}),
            "variant of another family": record(
                {"family": "xbox.xusb", "variant": "dongle"}
            ),
            "usb block on HID family": record(
                DUALSENSE, usb={"configuration": "set1-before-claim"}
            ),
            "usb block on GameSir enhanced HID": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "enhanced-hid",
                    "parameters": {"innerGrips": True},
                },
                usb={"configuration": "set1-before-claim"},
            ),
            "GameSir enhanced HID without a model parameter": record(
                {"family": "vendor.gamesir", "variant": "enhanced-hid"}
            ),
            "GameSir enhanced HID with both model parameters": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "enhanced-hid",
                    "parameters": {
                        "innerGrips": True,
                        "lightingMemory": "ProfileSlots",
                    },
                }
            ),
            "GameSir vendor USB inner grips": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "usb",
                    "parameters": {"innerGrips": True},
                }
            ),
            "GameSir vendor USB lighting slots": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "usb",
                    "parameters": {"lightingMemory": "ProfileSlots"},
                }
            ),
            "unknown parameter": record({**GIP, "parameters": {"sticksToNull": True}}),
            "wrong-family parameter": record(
                {**GIP, "parameters": {"innerGrips": True}}
            ),
            "legacy quirks array": record({**GIP, "quirks": ["share-offset"]}),
            "unknown DS4 parameter": record(
                {"family": "sony.dualshock4", "parameters": {"gyro": True}}
            ),
            "empty parameters": record({**GIP, "parameters": {}}),
            "wrong parameter type": record(
                {**GIP, "parameters": {"shareButton": {"fromEnd": "26"}}}
            ),
            "out-of-range share offset": record(
                {**GIP, "parameters": {"shareButton": {"fromEnd": 0}}}
            ),
            "unknown enum value": record(
                {"family": "nintendo.switch1", "parameters": {"layout": "joy-con-left"}}
            ),
            "false flag": record(
                {
                    "family": "vendor.gamesir",
                    "variant": "enhanced-hid",
                    "parameters": {"innerGrips": False},
                }
            ),
            "usb interface": record(GIP, usb={"interface": 1}),
            "startupPackets": record({**GIP, "startupPackets": ["xbox.gip/power-on"]}),
            "camelCase action": record({**GIP, "initialization": ["powerOn"]}),
            "XUSB initialization": record(
                {**XUSB, "initialization": ["xbox.gip/power-on"]}
            ),
            "both Joy-Con sides": record(
                {
                    "family": "nintendo.switch1",
                    "parameters": {"layout": ["JoyConLeft", "JoyConRight"]},
                }
            ),
            "GameCube on Switch 1": record(
                {"family": "nintendo.switch1", "parameters": {"layout": "GameCube"}}
            ),
            "Switch 2 with two layouts": record(
                {
                    "family": "nintendo.switch2",
                    "parameters": {"layout": ["GameCube", "JoyConLeft"]},
                }
            ),
            "Switch input-only with a parameter": record(
                {
                    "family": "nintendo.switch-input-only",
                    "parameters": {"layout": "GameCube"},
                }
            ),
            "Steam Deck with a parameter": record(
                {"family": "valve.steam-deck", "parameters": {"lizardMode": True}}
            ),
            "Steam Deck with a variant": record(
                {"family": "valve.steam-deck", "variant": "wired"}
            ),
            "Steam Triton without a variant": record({"family": "valve.steam-triton"}),
            "Steam Triton with a parameter": record(
                {
                    "family": "valve.steam-triton",
                    "variant": "wired",
                    "parameters": {"lizardMode": True},
                }
            ),
            "Switch 2 with a variant": record(
                {"family": "nintendo.switch2", "variant": "bluetooth-le"}
            ),
            "Switch 1 with a removed parameter": record(
                {"family": "nintendo.switch1", "parameters": {"switch2": True}}
            ),
            "Bluetooth-only with a layout": record(
                {
                    "family": "nintendo.switch1",
                    "parameters": {
                        "usbProtocol": "ChargingOnly",
                        "layout": "JoyConLeft",
                    },
                }
            ),
            "XUSB rumble absence": record(XUSB, capabilities={"rumble": "absent"}),
            "unknown control": record(GIP, capabilities={"absent": ["leftTrigger"]}),
            "empty capabilities": record(GIP, capabilities={}),
            "present on GIP": record(GIP, capabilities={"present": ["paddle-left-1"]}),
            "partial Edge controls": record(
                DUALSENSE, capabilities={"present": ["paddle-left-1", "auxiliary-1"]}
            ),
        }
        for protocol, parameters in (
            (GIP, ["shareOffset", "triggersToButtons", "inputOnly"]),
            (XUSB, ["dpadToButtons", "triggersToButtons"]),
            (
                {"family": "xbox.xid", "variant": "gamepad"},
                ["dpadToButtons", "sticksToNull", "triggersToButtons"],
            ),
            (DUALSENSE, ["edgeButtons", "microphoneMute", "touchpad"]),
            (
                {"family": "valve.steam-controller", "variant": "wired"},
                ["lizardMode", "trackpads"],
            ),
            (
                {"family": "nintendo.switch1"},
                ["usbHandshake", "joyConLeft", "joyConRight"],
            ),
        ):
            for parameter in parameters:
                removed[f"{protocol['family']} {parameter}"] = record(
                    {**protocol, "parameters": {parameter: True}}
                )
        for variant in ("gameSirG7ProUSB", "gameSirEnhancedHID", "enhanced-hid-8k"):
            removed[variant] = record({"family": "vendor.gamesir", "variant": variant})
        for name, document in removed.items():
            with self.subTest(name):
                self.assertFalse(self.validator.is_valid(document))

    def test_rejects_protocol_default_endpoints(self) -> None:
        defaults = (
            (GIP, 130, 2),
            (XUSB, 129, 1),
            ({"family": "xbox.xid", "variant": "gamepad"}, 129, 2),
            ({"family": "vendor.gamesir", "variant": "usb"}, 130, 2),
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


THIRD_PARTY = {"family": "vendor.ps3-third-party"}
GP100_RUMBLE = {
    "report": {"kind": "output", "id": 2, "length": 8},
    "leftMain": {"byte": 3},
    "rightMain": {"byte": 2},
}


class OwnershipAndOutputTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = validate_profiles.validator()

    def test_accepts_ownership_and_rumble_template(self) -> None:
        accepted = {
            "third-party rumble": record(THIRD_PARTY, output={"rumble": GP100_RUMBLE}),
            "OJD ownership": record(THIRD_PARTY, ownership="ojd"),
            "macOS ownership": record(DUALSENSE, ownership="macos"),
            "feature report": record(
                THIRD_PARTY,
                output={
                    "rumble": {
                        "report": {"kind": "feature", "id": 0, "length": 2},
                        "rightTrigger": {"byte": 1},
                    }
                },
            ),
        }
        for name, document in accepted.items():
            with self.subTest(name):
                self.assertTrue(self.validator.is_valid(document))

    def test_rejects_invalid_ownership_and_output(self) -> None:
        report = GP100_RUMBLE["report"]
        rejected = {
            "unknown ownership": record(THIRD_PARTY, ownership="native"),
            "GIP ownership": record(GIP, ownership="ojd"),
            "XUSB ownership": record(XUSB, ownership="macos"),
            "GameSir USB ownership": record(
                {"family": "vendor.gamesir", "variant": "usb"}, ownership="ojd"
            ),
            "template on DualSense": record(DUALSENSE, output={"rumble": GP100_RUMBLE}),
            "input report": record(
                THIRD_PARTY,
                output={
                    "rumble": {
                        "report": {**report, "kind": "input"},
                        "leftMain": {"byte": 3},
                    }
                },
            ),
            "no motor": record(THIRD_PARTY, output={"rumble": {"report": report}}),
            "haptic motor": record(
                THIRD_PARTY,
                output={"rumble": {"report": report, "leftHaptic": {"byte": 3}}},
            ),
            "unknown template": record(
                THIRD_PARTY, output={"rumble": GP100_RUMBLE, "lighting": {}}
            ),
            "empty output": record(THIRD_PARTY, output={}),
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


SIXAXIS = {"family": "sony.sixaxis"}
ENABLE = {
    "report": {"kind": "feature", "id": 244, "length": 5},
    "bytes": [66, 3, 0, 0],
    "transport": "bluetooth-classic",
}


class StartupWriteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = validate_profiles.validator()

    def test_accepts_startup_writes(self) -> None:
        accepted = {
            "Sixaxis enable": record(SIXAXIS, output={"startup": [ENABLE]}),
            "delayed output": record(
                DUALSENSE,
                output={
                    "startup": [
                        {
                            "report": {"kind": "output", "id": 0, "length": 2},
                            "bytes": [1, 2],
                            "delayMilliseconds": 1000,
                        }
                    ]
                },
            ),
            "startup with rumble": record(
                THIRD_PARTY, output={"rumble": GP100_RUMBLE, "startup": [ENABLE]}
            ),
        }
        for name, document in accepted.items():
            with self.subTest(name):
                self.assertTrue(self.validator.is_valid(document))

    def test_rejects_invalid_startup_writes(self) -> None:
        rejected = {
            "empty list": record(SIXAXIS, output={"startup": []}),
            "too many": record(SIXAXIS, output={"startup": [ENABLE] * 17}),
            "input report": record(
                SIXAXIS,
                output={
                    "startup": [
                        {**ENABLE, "report": {**ENABLE["report"], "kind": "input"}}
                    ]
                },
            ),
            "byte above 255": record(
                SIXAXIS, output={"startup": [{**ENABLE, "bytes": [256]}]}
            ),
            "no bytes": record(SIXAXIS, output={"startup": [{**ENABLE, "bytes": []}]}),
            "long delay": record(
                SIXAXIS, output={"startup": [{**ENABLE, "delayMilliseconds": 1001}]}
            ),
            "radio transport": record(
                SIXAXIS,
                output={
                    "startup": [{**ENABLE, "transport": "proprietary-radio-receiver"}]
                },
            ),
            "unknown key": record(
                SIXAXIS, output={"startup": [{**ENABLE, "repeat": 2}]}
            ),
            "GIP": record(GIP, output={"startup": [ENABLE]}),
            "XUSB": record(XUSB, output={"startup": [ENABLE]}),
            "GameSir USB": record(
                {"family": "vendor.gamesir", "variant": "usb"},
                output={"startup": [ENABLE]},
            ),
            "rumble on Sixaxis": record(
                SIXAXIS, output={"rumble": GP100_RUMBLE, "startup": [ENABLE]}
            ),
        }
        for name, document in rejected.items():
            with self.subTest(name):
                self.assertFalse(self.validator.is_valid(document))


REPORT_LAYOUT = {"family": "hid.report-layout"}
BUTTON = {"control": "face-south", "byte": 1, "mask": 1}
LAYOUT = {"report": {"length": 2}, "buttons": [BUTTON]}


class InputLayoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.validator = validate_profiles.validator()

    def test_accepts_report_layouts_and_dpad_pressure(self) -> None:
        accepted = {
            "one button": record(REPORT_LAYOUT, input=LAYOUT),
            "every section": record(
                REPORT_LAYOUT,
                input={
                    "report": {"id": 1, "length": 8},
                    "buttons": [BUTTON],
                    "axes": [
                        {
                            "control": "left-stick-x",
                            "byte": 2,
                            "bits": 16,
                            "signed": True,
                            "min": -32768,
                            "max": 32767,
                            "symmetric": True,
                        },
                        {"control": "left-stick-y", "byte": 4, "inverted": True},
                    ],
                    "hat": [
                        {
                            "encoding": "8-way",
                            "byte": 5,
                            "mask": 240,
                            "neutralUntilNonzero": True,
                        },
                        {
                            "encoding": "directions",
                            "up": {"byte": 6, "mask": 1},
                            "right": {"byte": 6, "mask": 2},
                            "down": {"byte": 6, "mask": 4},
                            "left": {"byte": 6, "mask": 8},
                        },
                        {
                            "encoding": "table",
                            "byte": 5,
                            "mask": 15,
                            "values": {"1": "north", "9": "northEast"},
                        },
                    ],
                    "leftTrigger": {"byte": 7},
                    "rightTrigger": {"button": {"byte": 1, "mask": 2}},
                },
            ),
            "layout with rumble": record(
                REPORT_LAYOUT, input=LAYOUT, output={"rumble": GP100_RUMBLE}
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
                input={**LAYOUT, "buttons": [{**BUTTON, "control": "dpad"}]},
            ),
            "12-bit axis": record(
                REPORT_LAYOUT,
                input={
                    **LAYOUT,
                    "axes": [{"control": "left-stick-x", "byte": 1, "bits": 12}],
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
                    "axes": [{"control": "left-stick-x", "byte": 1, "symmetric": True}],
                },
            ),
            "table hat without values": record(
                REPORT_LAYOUT,
                input={
                    **LAYOUT,
                    "hat": [{"encoding": "table", "byte": 1, "mask": 15, "values": {}}],
                },
            ),
            "table hat neutral entry": record(
                REPORT_LAYOUT,
                input={
                    **LAYOUT,
                    "hat": [
                        {
                            "encoding": "table",
                            "byte": 1,
                            "mask": 15,
                            "values": {"0": "neutral"},
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


STEAM = {"family": "valve.steam-controller"}
SWITCH1 = {"family": "nintendo.switch1"}
DS4 = {"family": "sony.dualshock4"}
DUALSENSE_MODEL_PARAMETERS = (
    {"unprobedSensors": True},
    {"unprobedTouchpad": True},
    {"forcedVibration": True},
    {"role": "Receiver"},
)


class SwiftParityTests(unittest.TestCase):
    """Rules `ControllerRecordDocument` enforces, which the schema must state too."""

    def setUp(self) -> None:
        self.validator = validate_profiles.validator()

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
        switch2 = {"family": "nintendo.switch2"}
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
        triton = {"family": "valve.steam-triton"}
        self.check(
            {
                f"triton {variant}": record({**triton, "variant": variant})
                for variant in ("wired", "dongle", "bluetooth-le")
            },
            {
                "triton without variant": record(triton),
                "triton unknown variant": record({**triton, "variant": "usb"}),
            },
        )

    def test_tuning_is_limited_to_its_families(self) -> None:
        liveness = {"inputLivenessTimeoutMs": 500}
        recovery = {"hidStartupRecoveryIntervalMs": 100, "hidStartupRecoveryRounds": 2}
        interval = {"hidStartupIntervalMs": 10}
        output = {"minimumHIDOutputIntervalMs": 8}
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
                        "family": "vendor.gamesir",
                        "variant": "enhanced-hid",
                        "parameters": {"innerGrips": True},
                    },
                    tuning=interval,
                ),
                "stick deadzone on GIP": record(GIP, tuning={"stickDeadzone": 0.1}),
            },
            {
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
                        "family": "nintendo.switch2",
                        "parameters": {"layout": "GameCube"},
                    },
                    tuning=recovery,
                ),
                "recovery on Switch input-only": record(
                    {"family": "nintendo.switch-input-only"}, tuning=recovery
                ),
                "startup interval on GIP": record(GIP, tuning=interval),
                "output interval on XUSB": record(XUSB, tuning=output),
                "startup interval on XID": record(
                    {"family": "xbox.xid", "variant": "gamepad"}, tuning=interval
                ),
                "output interval on GameSir USB": record(
                    {"family": "vendor.gamesir", "variant": "usb"}, tuning=output
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
                "absent": ["paddle-left-1"],
                "present": [
                    "paddle-left-1",
                    "paddle-right-1",
                    "auxiliary-1",
                    "auxiliary-2",
                ],
            },
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "record.json"
            path.write_text(json.dumps(overlapping))
            with self.assertRaises(validate_profiles.ValidationError):
                validate_profiles.validate_record(path, enforce_path=False)


if __name__ == "__main__":
    unittest.main()
