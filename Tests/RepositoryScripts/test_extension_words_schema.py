from __future__ import annotations

import unittest
from typing import Any

from Scripts.Catalog import schema_header
from Scripts.Quality import validate_schemas

SCHEMA = "cli-output.schema.json"


class ExtensionWordsSchemaTests(unittest.TestCase):
    """The CLI output schema accepts the transport-extension words and refuses the old."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.documents = validate_schemas.validate_schema_documents()
        cls.registry = validate_schemas.schema_registry(cls.documents)
        cls.defs: dict[str, Any] = cls.documents[SCHEMA]["$defs"]

    def validator(self, definition: str) -> Any:
        return validate_schemas.Draft202012Validator(
            {"$ref": f"#/$defs/{definition}", "$defs": self.defs},
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        )

    def status(self, kind: str) -> dict[str, Any]:
        return {
            **schema_header.header(kind),
            "bundle": "present",
            "registration": "active",
        }

    def test_a_transport_extension_status_is_valid(self) -> None:
        validator = self.validator("transportExtensionStatus")
        self.assertTrue(validator.is_valid(self.status("TransportExtension")))

    def test_the_old_driver_extension_kind_is_refused(self) -> None:
        validator = self.validator("transportExtensionStatus")
        self.assertFalse(validator.is_valid(self.status("DriverExtension")))

    def test_the_physical_ownership_enum_has_the_new_words_only(self) -> None:
        ownership = self.defs["controllerShow"]["properties"]["ownership"]["properties"]
        physical = ownership["physical"]["enum"]
        for new in ["ExtensionOwnedUsb", "SystemGamepad", "SystemHidVisible"]:
            self.assertIn(new, physical)
        for old in ["driverKitOwnedUSB", "nativeGamepad", "nativeHIDVisible"]:
            self.assertNotIn(old, physical)

    def test_the_duplicate_exposure_risk_enum_has_the_new_word_only(self) -> None:
        text = str(self.defs["controllerShow"]["properties"]["ownership"])
        self.assertIn("SystemHidVisible", text)
        self.assertNotIn("nativeHIDVisible", text)

    def test_a_record_names_its_transport_claim(self) -> None:
        for definition in ["recordShow", "sharedRecordValidation"]:
            properties = self.defs[definition]["properties"]
            self.assertNotIn("usbExtension", properties, definition)
            self.assertEqual(
                properties["transportClaim"]["enum"],
                ["claimed", "unclaimed"],
                definition,
            )


if __name__ == "__main__":
    unittest.main()
