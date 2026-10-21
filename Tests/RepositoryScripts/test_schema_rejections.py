"""The shared rejection files: Python refuses every listed document with its code and message, and
Swift reads every file in full, so no rejected document lacks a Swift counterpart."""

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
    def test_every_listed_record_is_refused_with_its_code_and_message(self) -> None:
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
            self.assertEqual(str(raised.exception), case["python"])
            self.assertTrue(str(raised.exception).startswith(f"{case['code']}: "))

    def test_every_listed_description_is_refused_with_its_code_and_message(
        self,
    ) -> None:
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
                        self.assertRaises(validate_schemas.ValidationError) as raised,
                    ):
                        validate_schemas.validate_protocol_descriptions(
                            schema, registry, [path]
                        )
                    self.assertEqual(str(raised.exception), case["python"])
                    self.assertTrue(
                        str(raised.exception).startswith(f"{case['code']}: ")
                    )

    def test_each_file_lists_distinct_named_documents_with_both_messages(self) -> None:
        for kind in schema_rejections.KINDS:
            listed = schema_rejections.cases(kind)
            self.assertGreater(len(listed), 100, kind)
            for case in listed:
                self.assertTrue(case["python"], case["name"])
                self.assertTrue(
                    case.get("swift"),
                    f"{case['name']} has no Swift message; run ./Scripts/ojd fixtures "
                    "regenerate schema-rejections --write",
                )
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

    def test_every_module_that_rejects_a_record_or_description_is_hooked(self) -> None:
        for module in schema_rejections.MODULES:
            source = (REPOSITORY / (module.replace(".", "/") + ".py")).read_text(
                encoding="utf-8"
            )
            self.assertRegex(source, r"enforce_(controller|description)_rejections\(\)")
        for path in sorted((REPOSITORY / "Tests/RepositoryScripts").glob("test_*.py")):
            source = path.read_text(encoding="utf-8")
            rejects = any(
                name in source
                for name in (
                    "validate_profiles.check_record",
                    "validate_profiles.validate_modes",
                    "validate_profiles.validate_record",
                    "validate_protocol_descriptions",
                    "RecordValidator",
                )
            )
            module = f"Tests.RepositoryScripts.{path.stem}"
            if rejects and path.stem != "test_schema_rejections":
                self.assertIn(module, schema_rejections.MODULES, path.name)

    def test_the_swift_tests_read_every_file_and_compare_codes_and_messages(
        self,
    ) -> None:
        source = SWIFT_TEST.read_text(encoding="utf-8")
        self.assertIn('for kind in ["controller", "protocol-description"]', source)
        self.assertIn('Self.cases("\\(kind).json")', source)
        self.assertIn("for fixture in cases", source)
        self.assertIn("ControllerRecordSet.problemCode(error)", source)
        self.assertIn("error.code.rawValue", source)
        self.assertIn('fixture["swift"]', source)
        # The patch cases pair the same way: Swift reads the file that Python reads.
        swift_patch = (
            REPOSITORY
            / "Tests/OpenJoystickDriverKitTests/Protocol/Catalog/ControllerPatchMergeTests.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("controller_patch/cases.json", swift_patch)


if __name__ == "__main__":
    unittest.main()
