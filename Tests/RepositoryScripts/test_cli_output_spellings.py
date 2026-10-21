import unittest
from typing import Any

from Scripts.Quality import validate_schemas

SCHEMA = "cli-output.schema.json"
VERSION = "openjoystickdriver/v1alpha1"
INTENSITIES = {
    key: 0
    for key in (
        "lowFrequency",
        "highFrequency",
        "leftTrigger",
        "rightTrigger",
        "leftHaptic",
        "rightHaptic",
    )
}


class CliOutputSpellingTests(unittest.TestCase):
    def setUp(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        self.schema: dict[str, Any] = documents[SCHEMA]
        self.registry = validate_schemas.schema_registry(documents)

    def accepts(self, pointer: str, value: Any) -> bool:
        return validate_schemas.Draft202012Validator(
            {"$ref": f"#{pointer}", "$defs": self.schema["$defs"]},
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        ).is_valid(value)

    def test_a_refused_token_takes_the_transport_in_upper_camel_case(self) -> None:
        token = {
            "reason": "E1002",
            "refusalTime": "2026-01-01T00:00:00Z",
            "scopes": ["Read"],
            "transport": "Web",
        }
        self.assertTrue(self.accepts("/$defs/sharedAccessRefusedToken", token))
        for transport in ("socket", "web"):
            with self.subTest(transport=transport):
                self.assertFalse(
                    self.accepts(
                        "/$defs/sharedAccessRefusedToken",
                        {**token, "transport": transport},
                    )
                )
        self.assertFalse(
            self.accepts(
                "/$defs/sharedAccessRefusedToken", {**token, "scopes": ["read"]}
            )
        )

    def test_a_virtual_feed_line_takes_the_rumble_types_in_upper_camel_case(
        self,
    ) -> None:
        header = {"apiVersion": VERSION, "kind": "RumbleCommand"}
        line = "/$defs/sharedVirtualFeedLine"
        self.assertTrue(
            self.accepts(
                line, {**header, "type": "SetRumble", "intensities": INTENSITIES}
            )
        )
        self.assertTrue(self.accepts(line, {**header, "type": "StopRumble"}))
        for type_name in ("setRumble", "stopRumble"):
            with self.subTest(type=type_name):
                self.assertFalse(
                    self.accepts(
                        line, {**header, "type": type_name, "intensities": INTENSITIES}
                    )
                )
        self.assertFalse(
            self.accepts(
                line,
                {
                    **header,
                    "type": "SetRumble",
                    "intensities": {**INTENSITIES, "leftMain": 0},
                },
            )
        )

    def test_acronym_values_take_the_acronym_in_upper_case(self) -> None:
        ownership = "/$defs/controllerShow/properties/ownership/properties"
        cases = (
            (f"{ownership}/physical", "ExtensionOwnedUSB", "ExtensionOwnedUsb"),
            (f"{ownership}/physical", "SystemHIDVisible", "SystemHidVisible"),
            (
                f"{ownership}/duplicateExposureRisk",
                "SystemHIDVisible",
                "SystemHidVisible",
            ),
            (
                "/$defs/controllerShow/properties/serving/properties/route",
                "VirtualHID",
                "VirtualHid",
            ),
        )
        for pointer, current, replaced in cases:
            with self.subTest(pointer=pointer, value=current):
                self.assertTrue(self.accepts(pointer, current))
                self.assertFalse(self.accepts(pointer, replaced))


if __name__ == "__main__":
    unittest.main()
