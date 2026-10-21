"""The shared rejection files: Python refuses every listed document with its code, and Swift reads
every file in full, so no rejected document lacks a Swift counterpart."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from Scripts.Catalog import validate_profiles
from Scripts.Quality import validate_schemas
from Tests.RepositoryScripts import schema_rejections

REPOSITORY = Path(__file__).resolve().parents[2]
SWIFT_TEST = (
    REPOSITORY
    / "Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejectionTests.swift"
)


class SchemaRejectionFileTests(unittest.TestCase):
    def test_every_listed_record_is_refused_with_its_code(self) -> None:
        schema = validate_profiles.validator()
        for case in schema_rejections.cases("controller"):
            with (
                self.subTest(case=case["name"]),
                self.assertRaises(validate_profiles.ValidationError) as raised,
            ):
                validate_profiles.check_record(
                    Path("record.json"), case["document"], schema
                )
            self.assertEqual(raised.exception.code, case["code"])
            self.assertTrue(str(raised.exception).startswith(f"{case['code']}: "))

    def test_every_listed_description_is_refused_with_its_code(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        registry = validate_schemas.schema_registry(documents)
        schema = documents["protocol-description.schema.json"]
        with tempfile.TemporaryDirectory(prefix="ojd-rejections-") as directory:
            root = Path(directory)
            with patch.object(validate_schemas, "ROOT", root):
                for case in schema_rejections.cases("protocol-description"):
                    path = root / case["fileName"]
                    path.write_text(json.dumps(case["document"]), encoding="utf-8")
                    with (
                        self.subTest(case=case["name"]),
                        self.assertRaisesRegex(
                            validate_schemas.ValidationError, rf"^{case['code']}: "
                        ),
                    ):
                        validate_schemas.validate_protocol_descriptions(
                            schema, registry, [path]
                        )

    def test_each_file_lists_distinct_named_documents(self) -> None:
        for kind in schema_rejections.KINDS:
            listed = schema_rejections.cases(kind)
            self.assertGreater(len(listed), 100, kind)
            names = [case["name"] for case in listed]
            self.assertEqual(len(names), len(set(names)), kind)
            documents = [
                schema_rejections.canonical(case["document"], case.get("fileName"))
                for case in listed
            ]
            self.assertEqual(len(documents), len(set(documents)), kind)

    def test_every_error_code_is_a_catalog_code(self) -> None:
        catalog = json.loads((REPOSITORY / "Resources/ErrorCodes.json").read_text())
        codes = {entry["code"] for entry in catalog["codes"]}
        for kind in schema_rejections.KINDS:
            for case in schema_rejections.cases(kind):
                self.assertIn(case["code"], codes, case["name"])

    def test_the_swift_tests_read_every_file_and_compare_codes(self) -> None:
        source = SWIFT_TEST.read_text(encoding="utf-8")
        for kind in schema_rejections.KINDS:
            self.assertIn(f'cases("{kind}.json")', source)
        self.assertIn("for fixture in cases", source)
        self.assertIn("ControllerRecordSet.problemCode(error)", source)
        self.assertIn("error.code.rawValue != code", source)
        # The patch cases pair the same way: Swift reads the file that Python reads.
        swift_patch = (
            REPOSITORY
            / "Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerPatchMergeTests.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("controller_patch/cases.json", swift_patch)


if __name__ == "__main__":
    unittest.main()
