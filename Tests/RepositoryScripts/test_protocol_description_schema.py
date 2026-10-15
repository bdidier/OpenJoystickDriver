from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from Scripts.Quality import validate_schemas

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_ID = (
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    "Resources/Schemas/v1beta1/protocol-description.schema.json"
)


def xusb_description() -> dict[str, Any]:
    return {
        "$schema": SCHEMA_ID,
        "family": "xbox.xusb",
        "interfaceSignatures": [
            {
                "variant": "wired",
                "interfaceClass": 255,
                "interfaceSubclass": 93,
                "interfaceProtocol": 1,
            }
        ],
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
        self, document: dict[str, Any], name: str | None = None
    ) -> None:
        with self.assertRaises(validate_schemas.ValidationError):
            self.check(document, name)

    def test_authored_descriptions_validate(self) -> None:
        paths = sorted(validate_schemas.PROTOCOL_DESCRIPTIONS.glob("*.json"))
        self.assertEqual(
            [path.stem for path in paths], ["xbox.gip", "xbox.xid", "xbox.xusb"]
        )
        with patch.object(validate_schemas, "ROOT", REPOSITORY_ROOT):
            validate_schemas.validate_protocol_descriptions(
                self.schema, self.registry, paths
            )

    def test_accepts_a_minimal_description(self) -> None:
        self.check(xusb_description())

    def test_rejects_a_wrong_schema_id(self) -> None:
        document = xusb_description()
        document["$schema"] = SCHEMA_ID.replace("v1beta1", "v1alpha1")
        self.assert_rejected(document)

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

    def test_rejects_missing_or_empty_signatures(self) -> None:
        empty = xusb_description()
        empty["interfaceSignatures"] = []
        self.assert_rejected(empty)
        missing = xusb_description()
        del missing["interfaceSignatures"]
        self.assert_rejected(missing)

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

    def test_rejects_a_duplicate_signature(self) -> None:
        document = xusb_description()
        signatures = document["interfaceSignatures"]
        signatures.append(copy.deepcopy(signatures[0]))
        self.assert_rejected(document)

    def family_variants(self) -> dict[str, list[str]]:
        """Each family's admitted variants; the Swift tests keep these equal to `variants`."""
        families: dict[str, list[str]] = {}
        for rule in self.schema["allOf"]:
            family = rule["if"]["properties"]["family"]["const"]
            signatures = rule["then"]["properties"]["interfaceSignatures"]
            families[family] = (
                signatures["items"]["properties"]["variant"]["enum"]
                if "items" in signatures
                else []
            )
        return families

    def described(self, family: str, variant: str) -> dict[str, Any]:
        document = xusb_description()
        document["family"] = family
        document["interfaceSignatures"][0]["variant"] = variant
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
                        self.assert_rejected(document)

    def test_rejects_a_file_name_that_differs_from_the_family(self) -> None:
        with self.assertRaisesRegex(
            validate_schemas.ValidationError, r"file name must be xbox\.xusb\.json"
        ):
            self.check(xusb_description(), name="xbox.gip.json")


if __name__ == "__main__":
    unittest.main()
