import unittest
from typing import Any

from Scripts.Catalog import schema_header
from Scripts.Quality import validate_schemas

SCHEMA = "cli-output.schema.json"
ROUTES = ("NativePassThrough", "VirtualHid", "ExtensionOwned", "OutputDisabled")


def claim_document(server: str = "ojd", previous: str = "system") -> dict[str, Any]:
    return {
        **schema_header.header("ControllerServer"),
        "controller": "xbox-1",
        "identity": "2C22:2000",
        "server": server,
        "previous": previous,
        "file": "/tmp/2c22-2000.patch.json",
        "created": True,
        "dryRun": False,
    }


class ControllerClaimSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        self.schema: dict[str, Any] = documents[SCHEMA]
        self.registry = validate_schemas.schema_registry(documents)

    def validator(self, name: str) -> Any:
        return validate_schemas.Draft202012Validator(
            {"$ref": f"#/$defs/{name}", "$defs": self.schema["$defs"]},
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        )

    def test_claim_sets_ojd_and_release_sets_system(self) -> None:
        self.validator("controllerClaim").validate(claim_document("ojd", "system"))
        self.validator("controllerRelease").validate(claim_document("system", "ojd"))
        for name, server in (
            ("controllerClaim", "system"),
            ("controllerRelease", "ojd"),
        ):
            with (
                self.subTest(name=name),
                self.assertRaises(validate_schemas.ValidationError),
            ):
                self.validator(name).validate(claim_document(server))

    def test_rejects_the_removed_ownership_words(self) -> None:
        for word in ("native", "virtual"):
            with (
                self.subTest(word=word),
                self.assertRaises(validate_schemas.ValidationError),
            ):
                self.validator("controllerClaim").validate(
                    claim_document(previous=word)
                )

    def test_the_ownership_command_has_no_schema(self) -> None:
        self.assertNotIn("controllerOwnership", self.schema["$defs"])

    def test_show_serving_names_every_route(self) -> None:
        show = self.schema["$defs"]["controllerShow"]
        self.assertEqual(
            show["properties"]["serving"]["properties"]["route"]["enum"], list(ROUTES)
        )
        self.assertIn("serving", show["required"])


if __name__ == "__main__":
    unittest.main()
