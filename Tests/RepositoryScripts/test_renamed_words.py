from __future__ import annotations

import re
import unittest
from pathlib import Path
from typing import Any

from Scripts.Quality import validate_schemas

TABLE = (
    Path(__file__).resolve().parents[2]
    / "Sources"
    / "OpenJoystickDriverKit"
    / "Errors"
    / "RenamedWord.swift"
)
ROW = re.compile(
    r'Self\(\s*old:\s*"([^"]+)",\s*new:\s*"([^"]+)",\s*'
    r'kind:\s*\.(flag|documentField)\((?:command|in):\s*"([^"]+)"\)\s*\)',
)


def rows() -> list[tuple[str, str, str, str]]:
    """(kind, where, old, new) of every flag and document-field row of `RenamedWord.all`."""
    return [
        (kind, where, old, new)
        for old, new, kind, where in ROW.findall(TABLE.read_text(encoding="utf-8"))
    ]


def property_names(node: Any) -> set[str]:
    """Every property name a schema subtree declares or requires."""
    names: set[str] = set()
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "properties" and isinstance(value, dict):
                names.update(value)
            elif key == "required" and isinstance(value, list):
                names.update(item for item in value if isinstance(item, str))
            names |= property_names(value)
    elif isinstance(node, list):
        for item in node:
            names |= property_names(item)
    return names


class RenamedWordsTests(unittest.TestCase):
    """The Swift table `RenamedWord.all` is the one list of renamed words; the schemas must agree."""

    def setUp(self) -> None:
        self.documents = validate_schemas.validate_schema_documents()
        self.registry = validate_schemas.schema_registry(self.documents)

    def location(self, where: str) -> Any:
        file, _, pointer = where.partition("#")
        node: Any = self.documents[file]
        for part in filter(None, pointer.split("/")):
            node = node[part]
        return node

    def test_the_table_is_read(self) -> None:
        kinds = {kind for kind, _, _, _ in rows()}

        self.assertIn("flag", kinds)
        self.assertIn("documentField", kinds)

    def test_no_schema_declares_an_old_field_and_each_declares_its_new_one(
        self,
    ) -> None:
        for kind, where, old, new in rows():
            if kind != "documentField":
                continue
            names = property_names(self.location(where))
            with self.subTest(old=old):
                self.assertNotIn(old, names)
                self.assertIn(new, names)

    def test_a_diagnosis_with_the_old_field_is_rejected(self) -> None:
        schema = self.documents["cli-output.schema.json"]
        validator = validate_schemas.Draft202012Validator(
            {"$ref": f"{schema['$id']}#/$defs/diagnose"},
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        )
        document = {
            "apiVersion": "openjoystickdriver/v1alpha1",
            "kind": "Diagnosis",
            "checks": [],
            "timings": [],
        }
        validator.validate({**document, "output": "/tmp/support.json"})

        with self.assertRaises(validate_schemas.ValidationError):
            validator.validate({**document, "bundle": "/tmp/support.json"})


if __name__ == "__main__":
    unittest.main()
