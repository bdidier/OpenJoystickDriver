"""The documents that Python's schema tests reject, shared with Swift's decoder tests.

`fixtures/schema_rejections/controller.json` and `protocol-description.json` list each rejected
document with the error code and the message each implementation gives it (`python`, `swift`).
`SchemaRejectionTests.swift` refuses every listed document with that code and message, and
`test_schema_rejections.py` does the same in Python, so a case cannot pass on another rule that
has the same code.

A Python test that rejects a document the files do not list fails until the document is added.
`./Scripts/ojd fixtures regenerate schema-rejections --write` records the rejections of the test
modules in `MODULES` into the files, and `--check` fails on a missing, changed or stale case.
While `collecting` is a dict the hooks add to it instead of failing.
"""

from __future__ import annotations

import functools
import inspect
import json
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from Scripts.Catalog import validate_profiles
from Scripts.Quality import validate_schemas

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "schema_rejections"
KINDS = ("controller", "protocol-description")
# The test modules whose rejections the files list; each calls the `enforce_` functions.
MODULES = (
    "Tests.RepositoryScripts.test_controller_modes",
    "Tests.RepositoryScripts.test_controller_schema",
    "Tests.RepositoryScripts.test_hid_usage_map_schema",
    "Tests.RepositoryScripts.test_protocol_description_schema",
    "Tests.RepositoryScripts.test_record_value_spelling",
)

# Set by the regenerate command: kind -> canonical document -> what the rejecting test gave.
collecting: dict[str, dict[str, dict[str, Any]]] | None = None


@functools.cache
def cases(kind: str) -> list[dict[str, Any]]:
    return json.loads((FIXTURES / f"{kind}.json").read_text(encoding="utf-8"))["cases"]


def canonical(document: Any, file_name: str | None = None) -> str:
    return json.dumps([file_name, document], sort_keys=True)


@functools.cache
def listed(kind: str) -> dict[str, dict[str, Any]]:
    return {
        canonical(case["document"], case.get("fileName")): case for case in cases(kind)
    }


def rejecting_test() -> tuple[str, str]:
    """The test method that is running and the label of its `subTest`."""
    for frame in inspect.stack()[2:]:
        test = frame.frame.f_locals.get("self")
        if frame.function.startswith("test_") and isinstance(test, unittest.TestCase):
            # `_subtest` is the running subTest context, whose `_message` is its label.
            subtest = getattr(test, "_subtest", None)
            label = getattr(subtest, "_message", None)
            params = getattr(subtest, "params", None)
            parts = [label] if isinstance(label, str) else []
            if params:
                parts.append(
                    ", ".join(f"{key}={value}" for key, value in params.items())
                )
            return frame.function, " ".join(parts)
    return "", ""


def require_listed(kind: str, document: Any, file_name: str | None = None) -> None:
    """Fails unless the shared file lists `document`; while collecting, records it instead."""
    key = canonical(document, file_name)
    if collecting is not None:
        test, label = rejecting_test()
        collecting[kind].setdefault(
            key,
            {"document": document, "fileName": file_name, "test": test, "label": label},
        )
        return
    if key not in listed(kind):
        entry = {"name": "<name the rule>", "document": document}
        if file_name is not None:
            entry["fileName"] = file_name
        raise TypeError(
            f"Python rejects a {kind} document that fixtures/schema_rejections/{kind}.json "
            "does not list, so Swift has no counterpart; run `./Scripts/ojd fixtures "
            f"regenerate schema-rejections --write`:\n{json.dumps(entry)}"
        )


def enforce_controller_rejections() -> None:
    """For the rest of the module, each record that `validate_profiles` rejects must be listed.

    Call from `setUpModule`.
    """

    def listing(name: str) -> None:
        original = getattr(validate_profiles, name)
        signature = inspect.signature(original)

        def wrapper(*args: Any, **kwargs: Any) -> Any:
            try:
                return original(*args, **kwargs)
            except validate_profiles.ValidationError:
                # Bound by name, so a keyword call is checked like a positional one.
                document = signature.bind(*args, **kwargs).arguments["record"]
                if not isinstance(document, dict):
                    raise TypeError(
                        f"{name} was given a record that is not a JSON object"
                    )
                require_listed("controller", document)
                raise

        patcher = patch.object(validate_profiles, name, wrapper)
        patcher.start()
        unittest.addModuleCleanup(patcher.stop)

    for name in ("check_record", "validate_modes", "validate_initialization"):
        listing(name)


def enforce_description_rejections() -> None:
    """For the rest of the module, each protocol description that `validate_schemas` rejects
    must be listed. Call from `setUpModule`."""
    original = validate_schemas.validate_protocol_descriptions

    def wrapper(schema: Any, registry: Any, paths: list[Path]) -> None:
        try:
            original(schema, registry, paths)
        except validate_schemas.ValidationError as error:
            # The error names the one file it refused, relative to the root.
            [path] = [path for path in paths if path.name in str(error)]
            require_listed(
                "protocol-description",
                json.loads(path.read_text(encoding="utf-8")),
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
