from __future__ import annotations

import json
import pathlib
import tempfile
import unittest

from Scripts.Catalog import catalog_rules
from Scripts.Catalog import generate_controller_catalog as catalog
from Scripts.Catalog import generate_xpad_records as xpad


class CatalogRulesLoadingTests(unittest.TestCase):
    def write(self, directory: str, document: dict[str, object]) -> None:
        (pathlib.Path(directory) / "rules.json").write_text(json.dumps(document))

    def test_parse_identity(self) -> None:
        self.assertEqual(catalog_rules.parse_identity("045E:02D1"), (0x045E, 0x02D1))
        for text in ("045E", "45E:02D1", "045E:zzzz", "045E:02D1:00"):
            with self.subTest(text=text), self.assertRaises(catalog_rules.RulesError):
                catalog_rules.parse_identity(text)

    def test_load_rules_rejects_wrong_header_and_keys(self) -> None:
        good = {
            "apiVersion": catalog_rules.API_VERSION,
            "kind": "Example",
            "values": [],
        }
        keys = frozenset({"values"})
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory)
            self.write(directory, good)
            loaded = catalog_rules.load_rules("rules.json", "Example", keys, path)
            self.assertEqual(loaded["values"], [])
            for change in (
                {"apiVersion": "openjoystickdriver.io/v1beta1"},
                {"kind": "Other"},
                {"extra": 1},
            ):
                with self.subTest(change=change):
                    self.write(directory, {**good, **change})
                    with self.assertRaises(catalog_rules.RulesError):
                        catalog_rules.load_rules("rules.json", "Example", keys, path)
            self.write(directory, {key: good[key] for key in ("apiVersion", "kind")})
            with self.assertRaises(catalog_rules.RulesError):
                catalog_rules.load_rules("rules.json", "Example", keys, path)
            with self.assertRaises(catalog_rules.RulesError):
                catalog_rules.load_rules("missing.json", "Example", keys, path)

    def test_sdl_rules_are_loaded_from_data(self) -> None:
        self.assertEqual(catalog.SONY_VENDOR_ID, 0x054C)
        self.assertEqual(
            catalog.SDL_FAMILIES["XBox360Controller"], ("xbox.xusb", "wired")
        )
        self.assertEqual(
            catalog.SDL_FAMILIES["PS4Controller"], ("sony.dualshock4", None)
        )
        self.assertEqual(
            catalog.SDL_IDENTITY_FAMILIES[(0x0955, 0x7210)],
            ("XBox360Controller", "vendor.nvidia-shield", None),
        )
        self.assertEqual(catalog.STEAM_VARIANTS[(0x28DE, 0x1304)], "dongle")
        self.assertEqual(catalog.SDL_QUIRKS["SwitchJoyConLeft"], ["joy-con-left"])
        self.assertIn((0x057E, 0x2066), catalog.SWITCH_2_IDENTITIES)
        self.assertEqual(
            catalog.BLUETOOTH_ONLY_IDENTITIES, {(0x0E6F, 0x0186), (0x0F0D, 0x00F6)}
        )
        self.assertEqual(
            catalog.SDL_EXCLUSIONS[(0x045E, 0x02A0)],
            ("XBox360Controller", catalog.INTERFACE_SIGNATURE_BUCKET),
        )
        self.assertEqual(len(catalog.SDL_EXCLUSIONS), 11)
        self.assertEqual(len(catalog.SDL_IDENTITY_FAMILIES), 13)
        self.assertEqual(len(catalog.STEAM_VARIANTS), 11)
        self.assertEqual(len(catalog.MICROSOFT_XBOX_360_PRODUCT_IDS), 6)
        self.assertEqual(
            catalog.SDL_XBOX_USB_TYPES,
            catalog.SDL_INTERFACE_SIGNATURE_TYPES
            | {"XBox360Controller", "XBoxOneController"},
        )

    def test_hid_rules_are_loaded_from_data(self) -> None:
        self.assertEqual(len(catalog.HID_RECORDS), 10)
        edge = [
            row for row in catalog.HID_RECORDS if row[2].endswith("PS5_CONTROLLER_2")
        ]
        self.assertEqual(len(edge), 1)
        self.assertEqual(
            edge[0][6],
            {
                "present": [
                    "paddle-left-1",
                    "paddle-right-1",
                    "auxiliary-1",
                    "auxiliary-2",
                ]
            },
        )
        steam = {
            row[2]: row[4] for row in catalog.HID_RECORDS if row[3].startswith("valve")
        }
        self.assertEqual(
            steam,
            {
                "USB_DEVICE_ID_STEAM_CONTROLLER": "wired",
                "USB_DEVICE_ID_STEAM_CONTROLLER_WIRELESS": "dongle",
            },
        )

    def test_xpad_rules_are_loaded_from_data(self) -> None:
        self.assertEqual(
            xpad.DRIVER_HANDLED_DEVICE_FLAGS, {("FLAG_DELAY_INIT", "XTYPE_XBOXONE")}
        )
        self.assertEqual(
            xpad.MAPPING_ORDER, (("MAP_SHARE_OFFSET", "share-offset", "xbox.gip"),)
        )
        self.assertEqual(xpad.CAPABILITY_ABSENCES[1][0], "MAP_TRIGGERS_TO_BUTTONS")
        self.assertEqual(
            xpad.SUPPORTED_TYPES["XTYPE_XBOX360W"], ("xbox.xusb", "receiver")
        )
        self.assertEqual(xpad.SUPPORTED_TYPES["XTYPE_XBOXONE"], ("xbox.gip", None))
        self.assertIsNone(xpad.TYPE_FILTERS["all"])
        self.assertEqual(xpad.TYPE_FILTERS["xbox.gip"], "XTYPE_XBOXONE")
        self.assertEqual(len(xpad.INIT_PACKET_NAMES), 8)
        self.assertEqual(
            xpad.DEFAULT_INITIALIZATION,
            ["xbox.gip/power-on", "xbox.gip/led-on", "xbox.gip/auth-done"],
        )
        self.assertEqual(len(xpad.DANCEPAD_FLAGS), 3)


if __name__ == "__main__":
    unittest.main()
