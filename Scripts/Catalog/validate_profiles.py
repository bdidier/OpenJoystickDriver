"""Validate canonical OpenJoystickDriver controller records."""

from __future__ import annotations

import json
import pathlib
import sys
from typing import Any

try:
    from jsonschema import Draft202012Validator
    from jsonschema.exceptions import ValidationError as JSONSchemaValidationError
    from referencing import Registry, Resource
except ImportError:
    print(
        "error: install schema validation dependencies with "
        "'python3 -m pip install -r Scripts/Quality/requirements.txt'",
        file=sys.stderr,
    )
    raise SystemExit(2)

from Scripts.Catalog.controller_patch import RAW_USB_FAMILIES

ROOT = pathlib.Path(__file__).resolve().parents[2]
# Families whose driver encodes rumble from a record's rumble template, as
# `PhysicalProtocolID.encodesRumbleTemplate` does in Swift.
RUMBLE_TEMPLATE_FAMILIES = frozenset({"hid.report-layout", "vendor.ps3-third-party"})
# `DualSenseDriver.edgeControls` in Swift.
DUALSENSE_EDGE_CONTROLS = frozenset(
    {"LeftPaddle1", "RightPaddle1", "Auxiliary1", "Auxiliary2"}
)
RECORD_DIR = ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
SCHEMA_PATH = ROOT / "Resources" / "Schemas" / "controller.schema.json"


class ValidationError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def uses_raw_usb(protocol: dict[str, Any]) -> bool:
    family = protocol["family"]
    return family in RAW_USB_FAMILIES or (
        family == "vendor.gamesir" and protocol.get("variant") == "usb"
    )


def capabilities_are_declared(record: dict[str, Any], family: str) -> bool:
    capabilities = record.get("capabilities", {})
    present = set(capabilities.get("present", []))
    present_allowed = not present or (
        family == "sony.dualsense" and present == DUALSENSE_EDGE_CONTROLS
    )
    rumble_allowed = "rumble" not in capabilities or family == "xbox.gip"
    return rumble_allowed and present_allowed


def usage_map_problem(usage_map: dict[str, Any]) -> str | None:
    """What JSON Schema cannot say about a hidUsageMap, as `HIDUsageMap.init` in Swift."""
    seen: set[tuple[int, int]] = set()
    for entry in usage_map["usages"]:
        key = (entry["page"], entry["usage"])
        if key in seen:
            return f"usage page {key[0]} usage {key[1]} appears more than once"
        seen.add(key)
        if entry["kind"] == "axis" and "range" in entry:
            bounds = entry["range"]
            if bounds["min"] >= bounds["max"]:
                return f"axis range {bounds['min']}...{bounds['max']} must have min below max"
    return None


def validate_modes(path: pathlib.Path, record: dict[str, Any]) -> None:
    """The record-level rules every mode's protocol obeys, as `validateModes` in Swift."""
    modes = record.get("modes", [])
    if not modes:
        return
    identifiers = [mode["id"] for mode in modes]
    require(
        len(set(identifiers)) == len(identifiers),
        f"{path}: mode IDs must be unique: {identifiers}",
    )
    has_layout = "input" in record
    has_template = "rumble" in record.get("output", {})
    for protocol in [record["protocol"], *(mode["protocol"] for mode in modes)]:
        family = protocol["family"]
        require(
            not uses_raw_usb(protocol),
            f"{path}: modes apply only to HID controllers",
        )
        require(
            has_layout == (family == "hid.report-layout"),
            f"{path}: every mode needs the record's input layout exactly when it is "
            "hid.report-layout",
        )
        require(
            not has_template or family in RUMBLE_TEMPLATE_FAMILIES,
            f"{path}: rumble templates require a driver that encodes them in every mode",
        )
        require(
            capabilities_are_declared(record, family),
            f"{path}: capabilities must be deltas the driver of every mode declares",
        )
    for mode in modes:
        for probe in mode["match"]["probes"]:
            if probe["expect"] == "bytes":
                end = probe["offset"] + len(probe["bytes"].split(" "))
                require(
                    end <= probe["length"],
                    f"{path}: mode {mode['id']} probe bytes end at {end}, "
                    f"past length {probe['length']}",
                )


def expected_relative_path(vendor_id: int, product_id: int) -> pathlib.Path:
    return pathlib.Path(f"{vendor_id:04x}") / f"{vendor_id:04x}-{product_id:04x}.json"


def load_object(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except json.JSONDecodeError as error:
        raise ValidationError(f"{path}: invalid JSON: {error}") from error
    require(isinstance(value, dict), f"{path}: root must be an object")
    return value


def schema_registry() -> Any:
    """Every schema under `Resources/Schemas`, so `vocabulary.schema.json` refs resolve."""
    resources = []
    for path in sorted(SCHEMA_PATH.parent.glob("*.schema.json")):
        document = load_object(path)
        resources.append((document["$id"], Resource.from_contents(document)))
    return Registry().with_resources(resources)


def validator() -> Any:
    schema = load_object(SCHEMA_PATH)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, registry=schema_registry())


def validate_record(
    path: pathlib.Path,
    *,
    enforce_path: bool = True,
    schema_validator: Any | None = None,
) -> tuple[int, int, str]:
    record = load_object(path)
    active_validator = schema_validator or validator()
    try:
        active_validator.validate(record)
    except JSONSchemaValidationError as error:
        location = ".".join(str(component) for component in error.absolute_path)
        suffix = f" at {location}" if location else ""
        raise ValidationError(f"{path}{suffix}: {error.message}") from error

    # JSON Schema cannot express disjoint arrays; the runtime decoder rejects overlap too.
    capabilities = record.get("capabilities", {})
    overlap = set(capabilities.get("absent", [])) & set(capabilities.get("present", []))
    require(
        not overlap, f"{path}: capabilities both absent and present: {sorted(overlap)}"
    )

    # JSON Schema cannot express unique usages or ordered axis ranges either.
    usage_map = record.get("input", {}).get("hidUsageMap")
    if usage_map is not None:
        problem = usage_map_problem(usage_map)
        require(problem is None, f"{path}: hidUsageMap: {problem}")

    # JSON Schema cannot express unique mode IDs, probe bytes that fit the read length, or the
    # record-level rules each mode obeys; the runtime decoder rejects all of them too.
    validate_modes(path, record)

    vendor_id = record["vendorID"]
    product_id = record["productID"]
    if enforce_path:
        relative = path.relative_to(RECORD_DIR)
        expected = expected_relative_path(vendor_id, product_id)
        require(relative == expected, f"{path}: path must be {expected}")

    return vendor_id, product_id, record["protocol"]["family"]


def validate_catalog(record_dir: pathlib.Path = RECORD_DIR) -> list[pathlib.Path]:
    records = sorted(record_dir.glob("*/*.json"))
    require(bool(records), f"no controller records found in {record_dir}")
    seen: dict[tuple[int, int], pathlib.Path] = {}
    schema_validator = validator()
    for path in records:
        vendor_id, product_id, _ = validate_record(
            path,
            enforce_path=record_dir == RECORD_DIR,
            schema_validator=schema_validator,
        )
        key = (vendor_id, product_id)
        require(key not in seen, f"{path}: duplicate identity also in {seen.get(key)}")
        seen[key] = path
    return records


def main() -> int:
    try:
        records = validate_catalog()
    except (OSError, ValidationError) as error:
        print(f"[FAIL] {error}", file=sys.stderr)
        return 1

    for path in records:
        print(f"[OK] {path.relative_to(ROOT)}")
    print(f"Validated {len(records)} canonical controller record(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
