"""The documents that Python's schema tests reject, shared with Swift's decoder tests.

`fixtures/schema_rejections/controller.json` and `protocol-description.json` list each rejected
document with the error code both implementations give it. `SchemaRejectionTests.swift` refuses
every listed document with that code, so a rule that only one side enforces fails there. A Python
test that rejects a document the files do not list fails until the document is added, which is
how a Python rule gets its Swift counterpart.
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from Scripts.Catalog import validate_profiles
from Scripts.Quality import validate_schemas

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "schema_rejections"
KINDS = ("controller", "protocol-description")


def cases(kind: str) -> list[dict[str, Any]]:
    return json.loads((FIXTURES / f"{kind}.json").read_text(encoding="utf-8"))["cases"]


def canonical(document: Any, file_name: str | None = None) -> str:
    return json.dumps([file_name, document], sort_keys=True)


def listed(kind: str) -> dict[str, dict[str, Any]]:
    return {
        canonical(case["document"], case.get("fileName")): case for case in cases(kind)
    }


def require_listed(
    kind: str, document: Any, code: str | None, file_name: str | None = None
) -> None:
    """Fails unless the shared file lists `document`, and with `code` when one is given."""
    case = listed(kind).get(canonical(document, file_name))
    if case is None:
        entry = {"name": "<name the rule>", "code": code, "document": document}
        if file_name is not None:
            entry["fileName"] = file_name
        raise AssertionError(
            f"Python rejects a {kind} document that fixtures/schema_rejections/{kind}.json "
            f"does not list, so Swift has no counterpart; add it:\n{json.dumps(entry)}"
        )
    if code is not None and case["code"] != code:
        raise AssertionError(
            f"{case['name']}: Python gives {code}, the shared file lists {case['code']}"
        )


def enforce_controller_rejections() -> None:
    """For the rest of the module, each record that `validate_profiles` rejects must be listed.

    Call from `setUpModule`.
    """

    def listing(name: str, position: int) -> None:
        original = getattr(validate_profiles, name)

        def wrapper(*args: Any, **kwargs: Any) -> Any:
            try:
                return original(*args, **kwargs)
            except validate_profiles.ValidationError:
                document = args[position] if len(args) > position else None
                if isinstance(document, dict):
                    require_listed("controller", document, None)
                raise

        patcher = patch.object(validate_profiles, name, wrapper)
        patcher.start()
        unittest.addModuleCleanup(patcher.stop)

    for name in ("check_record", "validate_modes", "validate_initialization"):
        listing(name, 1)


def enforce_description_rejections() -> None:
    """For the rest of the module, each protocol description that `validate_schemas` rejects must
    be listed. Call from `setUpModule`."""
    original = validate_schemas.validate_protocol_descriptions

    def wrapper(schema: Any, registry: Any, paths: list[Path]) -> None:
        try:
            original(schema, registry, paths)
        except validate_schemas.ValidationError as error:
            for path in paths:
                require_listed(
                    "protocol-description",
                    json.loads(path.read_text(encoding="utf-8")),
                    str(error).split(":", 1)[0],
                    path.name,
                )
            raise

    patcher = patch.object(validate_schemas, "validate_protocol_descriptions", wrapper)
    patcher.start()
    unittest.addModuleCleanup(patcher.stop)


class RecordValidator:
    """The schema plus every rule it cannot state, which the description-driven rules
    (variants, tuning scope, capability deltas) need."""

    def __init__(self) -> None:
        self.schema = validate_profiles.validator()

    def is_valid(self, document: dict[str, Any]) -> bool:
        try:
            validate_profiles.check_record(Path("record.json"), document, self.schema)
        except validate_profiles.ValidationError:
            return False
        return True
