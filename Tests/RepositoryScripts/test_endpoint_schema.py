from __future__ import annotations

import unittest
from typing import Any

from Scripts.Quality import validate_schemas

VERSION = "openjoystickdriver/v1alpha1"
NONCE = "A" * 43


def line(kind: str, **fields: Any) -> dict[str, Any]:
    return {"apiVersion": VERSION, "kind": kind, **fields}


def failure(code: str, **fields: Any) -> dict[str, Any]:
    return line("Status", status="Failure", code=code, message="text", **fields)


DETAILS = {"details": {"supportedAPIVersions": [VERSION]}}


class EndpointSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        self.validator = validate_schemas.Draft202012Validator(
            documents["endpoint.schema.json"],
            registry=validate_schemas.schema_registry(documents),
            format_checker=validate_schemas.FormatChecker(),
        )

    def valid(self, message: dict[str, Any]) -> bool:
        return self.validator.is_valid(message)

    def test_accepts_every_message_of_the_protocol(self) -> None:
        messages = [
            line("Challenge", nonce=NONCE),
            line("Hello", scopes=["read", "control"]),
            line("Welcome", version="0.6.0", scopes=["read"]),
            line("Subscription", stream="controllers", output=True),
            line("FeedRequest", **{"as": "Generic"}),
            line("FeedSession", **{"as": "SdlCompatible"}),
            line("Frame", buttons=["South"], axes={"LeftStickX": 0.5}),
            line("KeepAlive"),
            failure("E1001"),
            failure("E1004"),
            failure("E1010", **DETAILS),
            failure("E1011", **DETAILS),
            failure("E1012", **DETAILS),
        ]
        for message in messages:
            self.assertTrue(self.valid(message), message)

    def test_a_keep_alive_has_no_member_besides_the_header(self) -> None:
        self.assertTrue(self.valid(line("KeepAlive")))
        self.assertFalse(self.valid(line("KeepAlive", buttons=["south"])))
        self.assertFalse(self.valid({"kind": "KeepAlive"}))

    def test_the_header_codes_need_the_supported_versions_and_no_other_code_has_them(
        self,
    ) -> None:
        for code in ("E1010", "E1011", "E1012"):
            self.assertFalse(self.valid(failure(code)), code)
        empty = {"details": {"supportedAPIVersions": []}}
        self.assertFalse(self.valid(failure("E1010", **empty)))
        for code in ("E1001", "E1002", "E1004", "E1009"):
            self.assertFalse(self.valid(failure(code, **DETAILS)), code)

    def test_the_retired_unsupported_protocol_code_is_not_a_status_code(self) -> None:
        self.assertFalse(self.valid(failure("E1003", **DETAILS)))
        self.assertFalse(self.valid(failure("E1003")))

    def test_the_persona_ids_replace_the_profile_names(self) -> None:
        for name in ("hid-generic", "hid-xbox-one-s-bt", "generic", "Xbox"):
            self.assertFalse(self.valid(line("FeedRequest", **{"as": name})), name)
            self.assertFalse(self.valid(line("FeedSession", **{"as": name})), name)

    def test_the_old_api_version_is_not_accepted(self) -> None:
        old = "openjoystickdriver.io/v1beta1"
        self.assertFalse(
            self.valid({"apiVersion": old, "kind": "Hello", "scopes": ["read"]})
        )
        self.assertFalse(self.valid({**failure("E1010", **DETAILS), "apiVersion": old}))

    def test_a_line_needs_both_header_members(self) -> None:
        hello = line("Hello", scopes=["read"])
        self.assertTrue(self.valid(hello))
        for member in ("apiVersion", "kind"):
            self.assertFalse(
                self.valid(
                    {key: value for key, value in hello.items() if key != member}
                )
            )


if __name__ == "__main__":
    unittest.main()
