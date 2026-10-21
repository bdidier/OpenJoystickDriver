"""The shared rejection files: Python refuses every listed document with its code and message, and
Swift reads every file in full, so no rejected document lacks a Swift counterpart."""

from __future__ import annotations

import ast
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from Scripts.Catalog import generate_schema_rejections, validate_profiles
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

    def test_a_case_that_swift_accepts_leaves_the_files_unchanged(self) -> None:
        built = {
            "controller": [
                {"name": "first", "code": "E5007", "python": "p", "document": {}}
            ],
            "protocol-description": [
                {"name": "second", "code": "E5002", "python": "p", "document": {}}
            ],
        }
        messages = {"controller": {"first": "m"}, "protocol-description": {}}
        with tempfile.TemporaryDirectory() as directory:
            fixtures = Path(directory)
            held = {
                "controller": '{"cases": []}\n',
                "protocol-description": '{"cases": [1]}\n',
            }
            for kind, text in held.items():
                (fixtures / f"{kind}.json").write_text(text, encoding="utf-8")
            with (
                patch.object(schema_rejections, "FIXTURES", fixtures),
                patch.object(
                    generate_schema_rejections, "formatted", lambda _path, text: text
                ),
                patch.object(
                    generate_schema_rejections,
                    "record_swift_messages",
                    return_value=messages,
                ),
                self.assertRaisesRegex(
                    generate_schema_rejections.RejectionError,
                    r"protocol-description case 'second'",
                ),
            ):
                generate_schema_rejections.write(built)
            for kind, text in held.items():
                self.assertEqual(
                    (fixtures / f"{kind}.json").read_text(encoding="utf-8"), text
                )

    def test_hooked_modules_reject_through_the_record_validator_or_a_hooked_call(
        self,
    ) -> None:
        hooks = {"check_record", "validate_modes", "validate_initialization"}
        for module in schema_rejections.MODULES:
            path = REPOSITORY / (module.replace(".", "/") + ".py")
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for owner in ast.walk(tree):
                if not isinstance(owner, ast.ClassDef):
                    continue
                raw = self.raw_schemas(owner)
                for function in owner.body:
                    if not isinstance(function, ast.FunctionDef):
                        continue
                    calls = [n for n in ast.walk(function) if isinstance(n, ast.Call)]
                    hooked = any(
                        isinstance(call.func, ast.Attribute) and call.func.attr in hooks
                        for call in calls
                    )
                    for line in self.raw_negatives(function, calls, raw):
                        self.assertTrue(
                            hooked,
                            f"{path.name}:{line} rejects through the raw schema, which the "
                            "shared files cannot see; use RecordValidator or call a "
                            "validate_profiles check",
                        )

    @staticmethod
    def raw_schemas(owner: ast.ClassDef) -> set[str]:
        """The `self.` attributes of `owner` that hold the bare JSON Schema validator."""
        names = set()
        for node in ast.walk(owner):
            if (
                isinstance(node, ast.Assign)
                and isinstance(node.value, ast.Call)
                and ast.unparse(node.value.func) == "validate_profiles.validator"
            ):
                names.update(ast.unparse(target) for target in node.targets)
        return names

    @staticmethod
    def raw_negatives(
        function: ast.FunctionDef, calls: list[ast.Call], raw: set[str]
    ) -> list[int]:
        """Lines where the function treats the bare validator's verdict as a rejection."""
        local = {
            ast.unparse(target)
            for node in ast.walk(function)
            if isinstance(node, ast.Assign)
            and isinstance(node.value, ast.Call)
            and ast.unparse(node.value.func) == "validate_profiles.validator"
            for target in node.targets
        }
        names = raw | local

        def on_raw(call: ast.Call, attribute: str) -> bool:
            func = call.func
            return (
                isinstance(func, ast.Attribute)
                and func.attr == attribute
                and ast.unparse(func.value) in names
            )

        lines = [call.lineno for call in calls if on_raw(call, "iter_errors")]
        for call in calls:
            if (
                isinstance(call.func, ast.Attribute)
                and call.func.attr == "assertFalse"
                and any(
                    isinstance(inner, ast.Call) and on_raw(inner, "is_valid")
                    for argument in call.args
                    for inner in ast.walk(argument)
                )
            ):
                lines.append(call.lineno)
        return lines

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
