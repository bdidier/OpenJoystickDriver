from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from ..Catalog import protocol_descriptions
from ..Catalog.schema_header import (
    API_VERSION,
    KINDS,
    SCHEMA_SUFFIX,
    schema_id,
)
from ..Catalog.validate_profiles import usage_map_problem
from ..Command.execution import swift_command
from .schema_compatibility import IncompatibleSchemaError
from .schema_compatibility import check as check_compatibility

try:
    from jsonschema import Draft202012Validator, FormatChecker
    from jsonschema.exceptions import SchemaError, ValidationError
    from referencing import Registry, Resource
except ImportError:
    print(
        "error: install schema validation dependencies with "
        "'python3 -m pip install -r Scripts/Quality/requirements.txt'",
        file=sys.stderr,
    )
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "Resources" / "Schemas"
GENERATED_RECORDS = (
    ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
)
AUTHORED_CONTROLLERS = ROOT / "Resources" / "Controllers"
AUTHORED_PATCHES = ROOT / "Resources" / "ControllerPatches"
ERROR_CODES = ROOT / "Resources" / "ErrorCodes.json"
CROSSWALK = ROOT / "Resources" / "Vocabulary" / "crosswalk.json"
PROTOCOL_DESCRIPTIONS = ROOT / "Resources" / "Protocols"
VIRTUAL_DEVICES = ROOT / "Resources" / "VirtualDevices"
SAMPLE_PACKAGE = ROOT / "docs" / "sdk" / "sample"
ACCESS_GRANT_FIXTURES = (
    ROOT / "Tests" / "RepositoryScripts" / "fixtures" / "access_grants.json",
)
SETTINGS_FIXTURES = (
    ROOT / "Tests" / "RepositoryScripts" / "fixtures" / "settings.json",
)
# The schema of each kind of file in the sample mod package, by its folder. A `Controllers`
# file is a `ControllerPatch` or a `Controller`, which its `kind` tells apart.
SAMPLE_FOLDER_SCHEMAS = {
    "Controllers": "controller",
    "Personas": "virtual-device",
    "Profiles": "profile",
}


def load_json(path: Path) -> object:
    with path.open(encoding="utf-8") as source:
        return json.load(source)


def validate_schema_documents() -> dict[str, dict[str, object]]:
    documents: dict[str, dict[str, object]] = {}
    paths = sorted(SCHEMAS.glob(f"*{SCHEMA_SUFFIX}"))
    if not paths:
        raise SchemaError(f"no schemas in {SCHEMAS.relative_to(ROOT)}")
    for path in paths:
        document = load_json(path)
        if not isinstance(document, dict):
            raise SchemaError(f"{path.relative_to(ROOT)} must contain a JSON object")
        Draft202012Validator.check_schema(document)
        documents[path.name] = document
    return documents


def schema_registry(documents: dict[str, dict[str, object]]) -> Registry:
    resources = []
    for name, document in documents.items():
        identifier = document.get("$id")
        if not isinstance(identifier, str) or not identifier:
            raise SchemaError(f"Resources/Schemas/{name} must declare a nonempty $id")
        resources.append((identifier, Resource.from_contents(document)))
    return Registry().with_resources(resources)


def api_version_consts(value: object, where: str = "") -> list[tuple[str, object]]:
    """Every `const` in `value` that names an OJD `apiVersion`, with where it is."""
    found: list[tuple[str, object]] = []
    if isinstance(value, dict):
        const = value.get("const")
        if isinstance(const, str) and const.startswith("openjoystickdriver"):
            found.append((where, const))
        for key, child in value.items():
            found.extend(api_version_consts(child, f"{where}/{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found.extend(api_version_consts(child, f"{where}/{index}"))
    return found


def validate_schema_identity(documents: dict[str, dict[str, object]]) -> None:
    """Check each `$id`, `apiVersion` const, and `kind` const against the one source."""
    for name, document in documents.items():
        stem = name[: -len(SCHEMA_SUFFIX)]
        if document.get("$id") != schema_id(stem):
            raise SchemaError(
                f"Resources/Schemas/{name}: $id must be {schema_id(stem)}, "
                f"found {document.get('$id')}"
            )
        for where, const in api_version_consts(document):
            if const != API_VERSION:
                raise SchemaError(
                    f"Resources/Schemas/{name}{where}: apiVersion const must be "
                    f"{API_VERSION}, found {const}"
                )
        kind = KINDS.get(stem)
        if kind is None:
            continue
        properties = document.get("properties")
        if not isinstance(properties, dict):
            properties = {}
            # A schema that declares the header in each oneOf branch.
            for branch in document.get("oneOf", []):  # type: ignore[attr-defined]
                properties = {**properties, **branch.get("properties", {})}
        header = {
            member: properties.get(member, {}).get("const")
            for member in ("apiVersion", "kind")
        }
        if header != {"apiVersion": API_VERSION, "kind": kind}:
            raise SchemaError(
                f"Resources/Schemas/{name}: must require apiVersion {API_VERSION} "
                f"and kind {kind}, found {header}"
            )


def sample_documents() -> list[tuple[str, Path]]:
    """The files of the sample mod package with the schema each is read as."""
    found: list[tuple[str, Path]] = [("mod-package", SAMPLE_PACKAGE / "mod.json")]
    for folder, stem in SAMPLE_FOLDER_SCHEMAS.items():
        for path in sorted((SAMPLE_PACKAGE / folder).glob("*.json")):
            kind = load_json(path)
            patch = (
                isinstance(kind, dict) and kind.get("kind") == KINDS["controller-patch"]
            )
            found.append(
                (
                    "controller-patch" if folder == "Controllers" and patch else stem,
                    path,
                )
            )
    known = {path for _, path in found}
    unknown = sorted(set(SAMPLE_PACKAGE.rglob("*.json")) - known)
    if unknown:
        raise SchemaError(
            f"{unknown[0].relative_to(ROOT)}: no schema is named for this sample file"
        )
    return found


def validate_documents(
    schema: dict[str, object],
    registry: Registry,
    paths: list[Path],
) -> None:
    validator = Draft202012Validator(schema, registry=registry)
    for path in paths:
        document = load_json(path)
        try:
            validator.validate(document)
        except ValidationError as error:
            location = ".".join(str(component) for component in error.absolute_path)
            suffix = f" at {location}" if location else ""
            raise ValidationError(
                f"{path.relative_to(ROOT)}{suffix}: {error.message}"
            ) from error


# The catalog codes of an invalid protocol description, as ProtocolDescription.decode throws them.
UNSUPPORTED_API_VERSION = "E5001"
INVALID_PROTOCOL_DESCRIPTION = "E5002"
PROTOCOL_DESCRIPTION_FAMILY_MISMATCH = "E5003"
UNKNOWN_PROTOCOL_VARIANT = "E5004"


def protocol_description_code(error: ValidationError) -> str:
    """The catalog code for a schema failure.

    E5001 when apiVersion is missing or not the supported one, E5004 when a variant is not the
    family's, and E5002 for every other invalid field.
    """
    path = list(error.absolute_path)
    missing_version = (
        error.validator == "required" and not path and "'apiVersion'" in error.message
    )
    if path == ["apiVersion"] or missing_version:
        return UNSUPPORTED_API_VERSION
    # The schema forbids the signature list of a family with no variants with a false schema, and
    # jsonschema reports that failure on the list itself, without a path.
    forbidden_list = (
        error.validator is None
        and isinstance(error.instance, list)
        and all(isinstance(item, dict) and "variant" in item for item in error.instance)
    )
    # The per-family rules also bound the raw-USB variants and the variants that carry default
    # tuning; jsonschema reports the first on the list and the second on `defaults.variants`.
    names_variant = (
        (path[:1] == ["interfaceSignatures"] and path[-1:] == ["variant"])
        or forbidden_list
        or path == ["rawUSB"]
        or (
            path == ["defaults", "variants"]
            and error.validator in ("propertyNames", "enum", None)
        )
    )
    return UNKNOWN_PROTOCOL_VARIANT if names_variant else INVALID_PROTOCOL_DESCRIPTION


def validate_protocol_descriptions(
    schema: dict[str, object],
    registry: Registry,
    paths: list[Path],
) -> None:
    """Validates protocol descriptions; every failure names its error catalog code."""
    validator = Draft202012Validator(schema, registry=registry)
    for path in paths:
        document = load_json(path)
        try:
            validator.validate(document)
        except ValidationError as error:
            location = ".".join(str(component) for component in error.absolute_path)
            suffix = f" at {location}" if location else ""
            raise ValidationError(
                f"{protocol_description_code(error)}: {path.relative_to(ROOT)}{suffix}: "
                f"{error.message}"
            ) from error
        # JSON Schema cannot express unique usages or ordered axis ranges; the Swift decoder
        # rejects both too.
        defaults_input = (
            document.get("defaults", {}).get("input", {})
            if isinstance(document, dict)
            else {}
        )
        usage_maps = {"defaults.input.hidUsageMap": defaults_input.get("hidUsageMap")}
        for index, shape in enumerate(defaults_input.get("descriptorShapes", [])):
            usage_maps[f"defaults.input.descriptorShapes.{index}.hidUsageMap"] = shape[
                "hidUsageMap"
            ]
        for label, usage_map in usage_maps.items():
            problem = None if usage_map is None else usage_map_problem(usage_map)
            if problem is not None:
                raise ValidationError(
                    f"{INVALID_PROTOCOL_DESCRIPTION}: {path.relative_to(ROOT)} at "
                    f"{label}: {problem}"
                )
        # The app loads Resources/Protocols/<family>.json by family, so a renamed file would
        # otherwise fail only at launch.
        family = document.get("family") if isinstance(document, dict) else None
        if path.stem != family:
            raise ValidationError(
                f"{PROTOCOL_DESCRIPTION_FAMILY_MISMATCH}: {path.relative_to(ROOT)}: "
                f"file name must be {family}.json"
            )
        # The schema cannot say that a default tuning key is one the family reads, or that a
        # raw-USB variant is the family's.
        assert isinstance(document, dict)
        for code, message in protocol_descriptions.semantic_violations(
            document, family_variants(schema, str(family))
        ):
            raise ValidationError(f"{code}: {path.relative_to(ROOT)}: {message}")


def family_variants(schema: dict[str, Any], family: str) -> list[str]:
    """The variants of `family`, which the description schema holds per family.

    Raises `KeyError` for a family the schema has no rule for, so a family added to the
    controller schema without a description rule fails here instead of reading as having none.
    """
    rules = {
        rule["if"]["properties"]["family"]["const"]: rule["then"]["properties"][
            "defaults"
        ]["properties"]["variants"]
        for rule in schema["allOf"]
        if "const" in rule.get("if", {}).get("properties", {}).get("family", {})
    }
    if family not in rules:
        raise KeyError(f"protocol-description.schema.json has no rule for {family}")
    variants = rules[family]
    if isinstance(variants, bool):
        return []
    return list(variants["propertyNames"]["enum"])


def swift_binary_path() -> Path:
    subprocess.run(
        swift_command(["build", "--product", "OpenJoystickDriver"]),
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    bin_path = subprocess.run(
        swift_command(["build", "--show-bin-path"]),
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return Path(bin_path.stdout.strip()) / "OpenJoystickDriver"


def validate_live_support_report(schema: dict[str, object], registry: Registry) -> None:
    with tempfile.TemporaryDirectory(prefix="ojd-schema-") as directory:
        report_path = Path(directory) / "support-report.json"
        # argv[0] "ojd" selects the command line in the app executable. `diagnose` exits 1 when
        # a check fails, such as a missing extension on CI, and still writes the report.
        command = ["ojd", "diagnose", "--output", str(report_path)]
        result = subprocess.run(
            command,
            executable=swift_binary_path(),
            cwd=ROOT,
            env={**os.environ, "OJD_RUN_REPOSITORY_CLI": "1"},
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode not in {0, 1} or not report_path.is_file():
            raise subprocess.CalledProcessError(
                result.returncode, command, result.stdout, result.stderr
            )
        Draft202012Validator(
            schema,
            registry=registry,
            format_checker=FormatChecker(),
        ).validate(load_json(report_path))


def main() -> int:
    try:
        documents = validate_schema_documents()
        validate_schema_identity(documents)
        registry = schema_registry(documents)
        controller_records = sorted(GENERATED_RECORDS.glob("*/*.json"))
        authored = sorted(AUTHORED_CONTROLLERS.glob("*/*.json"))
        patches = sorted(
            [*AUTHORED_PATCHES.glob("*.json"), *AUTHORED_PATCHES.glob("*/*.json")]
        )
        protocols = sorted(PROTOCOL_DESCRIPTIONS.glob("*.json"))
        virtual_devices = sorted(VIRTUAL_DEVICES.glob("*.json"))
        validate_documents(
            documents["controller.schema.json"], registry, controller_records
        )
        validate_documents(documents["controller.schema.json"], registry, authored)
        validate_documents(documents["controller-patch.schema.json"], registry, patches)
        validate_documents(
            documents["error-codes.schema.json"], registry, [ERROR_CODES]
        )
        validate_documents(documents["crosswalk.schema.json"], registry, [CROSSWALK])
        validate_protocol_descriptions(
            documents["protocol-description.schema.json"], registry, protocols
        )
        validate_documents(
            documents["virtual-device.schema.json"], registry, virtual_devices
        )
        samples = sample_documents()
        for stem, path in samples:
            validate_documents(documents[f"{stem}{SCHEMA_SUFFIX}"], registry, [path])
        validate_documents(
            documents["access-grants.schema.json"],
            registry,
            list(ACCESS_GRANT_FIXTURES),
        )
        validate_documents(
            documents["settings.schema.json"], registry, list(SETTINGS_FIXTURES)
        )
        validate_live_support_report(documents["report.schema.json"], registry)
        compatibility = check_compatibility(ROOT, documents)
    except (
        OSError,
        json.JSONDecodeError,
        SchemaError,
        ValidationError,
        IncompatibleSchemaError,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or error.stdout.strip() or str(error)
        print(f"error: {detail}", file=sys.stderr)
        return 1
    print(
        f"Validated {len(documents)} schema documents, "
        f"{len(controller_records)} controller records, {len(authored)} authored controllers, "
        f"{len(patches)} built-in patches, "
        f"{len(protocols)} protocol descriptions, "
        f"{len(virtual_devices)} virtual devices, {len(samples)} sample mod files, "
        f"{len(ACCESS_GRANT_FIXTURES)} access grant fixtures, "
        f"{len(SETTINGS_FIXTURES)} settings fixtures, the error code catalog, the control crosswalk, "
        "and one live support report."
    )
    print(compatibility)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
