"""Check or rebuild the shared schema rejection files.

`Tests/RepositoryScripts/fixtures/schema_rejections/` lists every document that Python's schema
tests reject, with the code and message of each side. This script runs the Python test modules in
`schema_rejections.MODULES` in collecting mode, so each rejected document is recorded instead of
failing, and builds the files from what they reject. `--write` then runs
`SchemaRejectionTests` in Swift in recording mode to fill in the Swift messages. `--check` fails
on a missing, changed or stale case, or a case without its Swift message.
"""

from __future__ import annotations

import argparse
import io
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
from Scripts.Catalog import validate_profiles
from Scripts.Command.execution import env_with, swift_command
from Scripts.Quality import biome_format, validate_schemas
from Tests.RepositoryScripts import schema_rejections

SWIFT_MESSAGES_ENVIRONMENT = "OJD_SCHEMA_REJECTION_MESSAGES"


class RejectionError(Exception):
    pass


def collect() -> dict[str, dict[str, dict[str, Any]]]:
    """The documents the Python test modules reject, by kind and canonical document."""
    collected: dict[str, dict[str, dict[str, Any]]] = {
        kind: {} for kind in schema_rejections.KINDS
    }
    schema_rejections.collecting = collected
    try:
        suite = unittest.defaultTestLoader.loadTestsFromNames(schema_rejections.MODULES)
        result = unittest.TextTestRunner(stream=io.StringIO(), verbosity=0).run(suite)
    finally:
        schema_rejections.collecting = None
    if not result.wasSuccessful():
        raise RejectionError(
            f"the schema test modules fail while collecting: {len(result.failures)} failures, "
            f"{len(result.errors)} errors; run them with unittest"
        )
    return collected


def case_name(test: str, label: str, taken: set[str]) -> str:
    base = test.removeprefix("test_").replace("_", " ")
    if label.strip():
        base = f"{base}: {label.strip()}"
    name, count = base, 1
    while name in taken:
        count += 1
        name = f"{base} ({count})"
    taken.add(name)
    return name


def controller_cases(collected: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    schema = validate_profiles.validator()
    taken: set[str] = set()
    cases = []
    for entry in collected.values():
        try:
            validate_profiles.check_record(
                Path("record.json"), entry["document"], schema
            )
        except validate_profiles.ValidationError as error:
            code, message = error.code, str(error)
        else:
            raise RejectionError(
                f"{entry['test']}: Python accepts the document it rejected"
            )
        cases.append(
            {
                "name": case_name(entry["test"], entry["label"], taken),
                "code": code,
                "python": message,
                "document": entry["document"],
            }
        )
    return cases


def description_cases(collected: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    documents = validate_schemas.validate_schema_documents()
    registry = validate_schemas.schema_registry(documents)
    schema = documents["protocol-description.schema.json"]
    taken: set[str] = set()
    cases = []
    with tempfile.TemporaryDirectory(prefix="ojd-rejections-") as directory:
        root = Path(directory)
        with patch.object(validate_schemas, "ROOT", root):
            for entry in collected.values():
                path = root / entry["fileName"]
                path.write_text(json.dumps(entry["document"]), encoding="utf-8")
                try:
                    validate_schemas.validate_protocol_descriptions(
                        schema, registry, [path]
                    )
                except validate_schemas.ValidationError as error:
                    message = str(error)
                else:
                    raise RejectionError(
                        f"{entry['test']}: Python accepts the document it rejected"
                    )
                match = re.match(r"(E\d{4}): ", message)
                if match is None:
                    raise RejectionError(f"{entry['test']}: {message} names no code")
                cases.append(
                    {
                        "name": case_name(entry["test"], entry["label"], taken),
                        "code": match.group(1),
                        "python": message,
                        "fileName": entry["fileName"],
                        "document": entry["document"],
                    }
                )
    return cases


def with_swift_messages(kind: str, cases: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """The cases, each with the Swift message the files already hold for its document."""
    known = {
        schema_rejections.canonical(case["document"], case.get("fileName")): case
        for case in current(kind)
    }
    merged = []
    for case in cases:
        before = known.get(
            schema_rejections.canonical(case["document"], case.get("fileName"))
        )
        if before is not None and "swift" in before:
            case = {**case, "swift": before["swift"]}
        merged.append(order(case))
    return merged


def order(case: dict[str, Any]) -> dict[str, Any]:
    keys = ("name", "code", "python", "swift", "fileName", "document")
    return {key: case[key] for key in keys if key in case}


def current(kind: str) -> list[dict[str, Any]]:
    path = schema_rejections.FIXTURES / f"{kind}.json"
    if not path.is_file():
        return []
    return json.loads(path.read_text(encoding="utf-8"))["cases"]


def render(cases: list[dict[str, Any]]) -> str:
    return json.dumps({"cases": cases}, indent=2, ensure_ascii=False) + "\n"


def formatted(path: Path, text: str) -> str:
    """`text` as Biome formats the JSON file `path`."""
    return biome_format.format_json({path: text})[path]


def build() -> dict[str, list[dict[str, Any]]]:
    collected = collect()
    return {
        "controller": with_swift_messages(
            "controller", controller_cases(collected["controller"])
        ),
        "protocol-description": with_swift_messages(
            "protocol-description",
            description_cases(collected["protocol-description"]),
        ),
    }


def record_swift_messages() -> dict[str, dict[str, str]]:
    """The Swift message of every case, from `SchemaRejectionTests` in recording mode."""
    with tempfile.TemporaryDirectory(prefix="ojd-rejections-") as directory:
        target = Path(directory) / "messages.json"
        completed = subprocess.run(
            swift_command(["test", "--filter", "SchemaRejectionTests"]),
            cwd=ROOT,
            env=env_with({SWIFT_MESSAGES_ENVIRONMENT: str(target)}),
            check=False,
            capture_output=True,
            text=True,
        )
        if not target.is_file():
            sys.stderr.write(completed.stdout + completed.stderr)
            raise RejectionError("SchemaRejectionTests recorded no Swift messages")
        return json.loads(target.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true")
    action.add_argument("--write", action="store_true")
    arguments = parser.parse_args()
    try:
        built = build()
        if arguments.write:
            for kind, cases in built.items():
                path = schema_rejections.FIXTURES / f"{kind}.json"
                path.write_text(formatted(path, render(cases)), encoding="utf-8")
            messages = record_swift_messages()
            for kind, cases in built.items():
                path = schema_rejections.FIXTURES / f"{kind}.json"
                for case in cases:
                    case["swift"] = messages[kind][case["name"]]
                path.write_text(
                    formatted(path, render([order(case) for case in cases])),
                    encoding="utf-8",
                )
            print("Generated the schema rejection files.")
            return 0
        stale = False
        for kind, cases in built.items():
            path = schema_rejections.FIXTURES / f"{kind}.json"
            if path.read_text(encoding="utf-8") != formatted(path, render(cases)):
                stale = True
                print(
                    f"error: {path.relative_to(ROOT)} differs from what the Python schema tests "
                    "reject, or lacks a Swift message; run: ./Scripts/ojd fixtures regenerate "
                    "schema-rejections --write",
                    file=sys.stderr,
                )
        return 1 if stale else 0
    except (RejectionError, OSError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
