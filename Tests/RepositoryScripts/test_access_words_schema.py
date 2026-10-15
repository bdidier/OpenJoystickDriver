from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path
from typing import Any

from Scripts.Quality import validate_schemas

ROOT = validate_schemas.ROOT
FIXTURES = Path(__file__).resolve().parent / "fixtures"
SAMPLE_PROFILE = ROOT / "docs" / "sdk" / "sample" / "Profiles" / "sample-pad.json"


def load(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as source:
        return json.load(source)


class AccessWordsSchemaTests(unittest.TestCase):
    """The schemas accept the permission, publisher, app, and modifier words and refuse the old."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.documents = validate_schemas.validate_schema_documents()
        cls.registry = validate_schemas.schema_registry(cls.documents)

    def validator(self, name: str) -> Any:
        return validate_schemas.Draft202012Validator(
            self.documents[name],
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        )

    def profile(self, **scope: str) -> dict[str, Any]:
        profile = load(SAMPLE_PROFILE)
        profile["applicationScope"] = {"type": "application", **scope}
        return profile

    def with_modifiers(self, modifiers: list[str]) -> dict[str, Any]:
        profile = load(SAMPLE_PROFILE)
        profile["bindings"][0]["destination"] = {
            "type": "keyboard",
            "key": "space",
            "modifiers": modifiers,
        }
        return profile

    def test_a_profile_scoped_by_app_id_is_valid(self) -> None:
        self.assertTrue(
            self.validator("profile.schema.json").is_valid(
                self.profile(appID="com.example.game")
            )
        )

    def test_a_profile_scoped_by_bundle_identifier_is_refused(self) -> None:
        self.assertFalse(
            self.validator("profile.schema.json").is_valid(
                self.profile(bundleIdentifier="com.example.game")
            )
        )

    def test_the_modifiers_meta_and_alt_are_valid(self) -> None:
        profile = self.with_modifiers(["alt", "control", "meta", "shift"])
        self.assertTrue(self.validator("profile.schema.json").is_valid(profile))

    def test_the_modifiers_command_and_option_are_refused(self) -> None:
        validator = self.validator("profile.schema.json")
        for old in ["command", "option"]:
            self.assertFalse(validator.is_valid(self.with_modifiers([old])), old)

    def test_a_grant_with_a_signed_publisher_is_valid(self) -> None:
        grants = load(FIXTURES / "access_grants.json")
        self.assertEqual(grants["grants"][0]["publisher"]["kind"], "signed")
        self.assertTrue(self.validator("access-grants.schema.json").is_valid(grants))

    def test_a_grant_with_a_platform_publisher_is_valid(self) -> None:
        grants = load(FIXTURES / "access_grants.json")
        grants["grants"][0]["publisher"] = {"kind": "platform"}
        self.assertTrue(self.validator("access-grants.schema.json").is_valid(grants))

    def test_a_grant_with_an_old_publisher_kind_is_refused(self) -> None:
        validator = self.validator("access-grants.schema.json")
        for old in ["team", "apple"]:
            grants = load(FIXTURES / "access_grants.json")
            grants["grants"][0]["publisher"]["kind"] = old
            self.assertFalse(validator.is_valid(grants), old)

    def test_a_grant_with_the_old_publisher_fields_is_refused(self) -> None:
        grants = load(FIXTURES / "access_grants.json")
        grant = grants["grants"][0]
        grant["kind"] = "team"
        grant["teamIdentifier"] = grant.pop("publisher")["id"]
        self.assertFalse(self.validator("access-grants.schema.json").is_valid(grants))

    def test_a_signed_publisher_needs_an_id(self) -> None:
        grants = load(FIXTURES / "access_grants.json")
        del grants["grants"][0]["publisher"]["id"]
        self.assertFalse(self.validator("access-grants.schema.json").is_valid(grants))

    def test_a_report_with_the_old_permission_fields_is_refused(self) -> None:
        validator = self.validator("report.schema.json")
        report = load(FIXTURES / "support_report_binding.json")
        self.assertTrue(validator.is_valid(report))
        for new, old in [
            ("inputRead", "inputMonitoring"),
            ("inputInject", "accessibility"),
        ]:
            renamed = copy.deepcopy(report)
            permissions = self.find_permissions(renamed)
            permissions[old] = permissions.pop(new)
            self.assertFalse(validator.is_valid(renamed), old)

    def find_permissions(self, document: Any) -> dict[str, Any]:
        stack = [document]
        while stack:
            node = stack.pop()
            if isinstance(node, dict):
                if "inputRead" in node and "inputInject" in node:
                    return node
                stack.extend(node.values())
            elif isinstance(node, list):
                stack.extend(node)
        raise AssertionError("no permission block in the report")


if __name__ == "__main__":
    unittest.main()
