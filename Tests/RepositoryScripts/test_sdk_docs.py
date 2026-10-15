from __future__ import annotations

import json
import re
import unittest
from pathlib import Path
from typing import Any

from Scripts.Quality import validate_schemas

ROOT = Path(__file__).resolve().parents[2]
PAGE = ROOT / "docs" / "sdk" / "endpoint.md"
CLIENT_KINDS = {"Hello", "Subscription", "FeedRequest", "Frame"}
DOCUMENTED_KINDS = {
    "Challenge",
    "Hello",
    "Welcome",
    "Subscription",
    "FeedRequest",
    "FeedSession",
    "Frame",
    "RumbleCommand",
    "Status",
    "AccessGrants",
}


def examples() -> list[dict[str, Any]]:
    """Every `json` block of the page, which holds one JSON object each."""
    text = PAGE.read_text(encoding="utf-8")
    blocks = re.findall(r"^```json\n(.*?)^```$", text, re.MULTILINE | re.DOTALL)
    return [json.loads(block) for block in blocks]


class SDKDocsTests(unittest.TestCase):
    def setUp(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        registry = validate_schemas.schema_registry(documents)

        def validator(schema: str, name: str = "") -> Any:
            reference = documents[schema]["$id"]
            if name:
                reference = f"{reference}#/$defs/{name}"
            return validate_schemas.Draft202012Validator(
                {"$ref": reference}, registry=registry
            )

        self.client_lines = validator("endpoint.schema.json", "clientLine")
        self.service_lines = validator("endpoint.schema.json", "serviceLine")
        self.grants = validator("access-grants.schema.json")

    def validator(self, example: dict[str, Any]) -> Any:
        kind = example.get("kind")
        if kind == "AccessGrants":
            return self.grants
        return self.client_lines if kind in CLIENT_KINDS else self.service_lines

    def test_every_example_validates_against_the_schema(self) -> None:
        for example in examples():
            with self.subTest(example=example):
                self.validator(example).validate(example)

    def test_the_examples_cover_every_message_kind(self) -> None:
        kinds = {example.get("kind") for example in examples()}
        self.assertTrue(DOCUMENTED_KINDS <= kinds, DOCUMENTED_KINDS - kinds)

    def test_the_examples_cover_a_watch_line(self) -> None:
        self.assertTrue(any("type" in example for example in examples()))

    def test_the_examples_name_the_endpoint_api_version(self) -> None:
        for example in examples():
            version = example.get("apiVersion") or example["object"]["apiVersion"]
            self.assertEqual(version, "openjoystickdriver/v1alpha1")

    def test_a_bad_example_would_fail(self) -> None:
        bad = {"apiVersion": "openjoystickdriver.io/v1beta1", "kind": "Hello"}
        with self.assertRaises(validate_schemas.ValidationError):
            self.client_lines.validate(bad)

    def test_the_error_table_lists_every_endpoint_code(self) -> None:
        catalog = json.loads(
            (ROOT / "Resources" / "ErrorCodes.json").read_text(encoding="utf-8")
        )
        expected = {
            entry["code"]: entry["name"]
            for entry in catalog["codes"]
            if entry["domain"] == "endpoint"
        }
        rows = re.findall(
            r"^\| `(E\d{4})` \| `(\w+)` \|",
            PAGE.read_text(encoding="utf-8"),
            re.MULTILINE,
        )
        self.assertEqual(dict(rows), expected)

    def test_the_page_names_the_persona_ids_only(self) -> None:
        text = PAGE.read_text(encoding="utf-8")
        for old in ("hid-generic", "hid-xbox"):
            self.assertNotIn(old, text)


if __name__ == "__main__":
    unittest.main()
