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

from Scripts.Catalog import protocol_descriptions

ROOT = pathlib.Path(__file__).resolve().parents[2]
RECORD_DIR = ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
SCHEMA_PATH = ROOT / "Resources" / "Schemas" / "controller.schema.json"


# The catalog codes of a record that is not valid, as `ControllerRecordSet.problemCode` reports
# them in Swift.
UNSUPPORTED_API_VERSION = "E5001"
INVALID_CONTROLLER_RECORD = "E5007"


class ValidationError(Exception):
    """A rule a record or catalog breaks; `code` is its catalog code and leads the message."""

    def __init__(self, message: str, code: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message, INVALID_CONTROLLER_RECORD)


def description_of(family: str) -> dict[str, Any]:
    return protocol_descriptions.bundled()[family]


def uses_raw_usb(protocol: dict[str, Any]) -> bool:
    return protocol_descriptions.uses_raw_usb(
        description_of(protocol["family"]), protocol.get("variant")
    )


def declares_keep_alive(family: str) -> bool:
    """Whether the family's description declares its own keep-alive."""
    return "keepAlive" in description_of(family).get("defaults", {}).get("session", {})


def encodes_rumble_template(family: str) -> bool:
    """Whether the family's driver encodes rumble from a record's rumble template."""
    return "rumble" in description_of(family).get("recordSections", ())


def reads_record_rumble_template(protocol: dict[str, Any]) -> bool:
    """Whether the driver of the protocol's family, variant and parameters encodes rumble from a
    record's rumble template, as `PhysicalProtocolID.readsRecordRumbleTemplate` in Swift: GameSir
    reads it only for enhanced HID and NVIDIA SHIELD only for the 2015 controller."""
    family = protocol["family"]
    if not encodes_rumble_template(family):
        return False
    if family == "VendorGameSir":
        return protocol.get("variant") == "EnhancedHID"
    if family == "VendorNVIDIAShield":
        return protocol.get("parameters", {}).get("reportRevision") == "Shield2015"
    return True


def requires_record_input_layout(family: str) -> bool:
    """Whether records of the family need an input layout of their own: the driver reads one
    and the description supplies none."""
    description = description_of(family)
    return "input" in description.get(
        "recordSections", ()
    ) and "input" not in description.get("defaults", {})


def capabilities_are_declared(record: dict[str, Any], family: str) -> bool:
    capabilities = record.get("capabilities", {})
    return protocol_descriptions.record_capabilities_permit(
        description_of(family),
        set(capabilities.get("present", [])),
        "rumble" in capabilities,
    )


def usage_map_problem(usage_map: dict[str, Any]) -> str | None:
    """What JSON Schema cannot say about a hidUsageMap, as `HIDUsageMap.init` in Swift."""
    seen: set[tuple[int, int]] = set()
    for entry in usage_map["usages"]:
        key = (entry["page"], entry["usage"])
        if key in seen:
            return f"usage page {key[0]} usage {key[1]} appears more than once"
        seen.add(key)
        if entry["kind"] == "Axis" and "range" in entry:
            bounds = entry["range"]
            if bounds["min"] >= bounds["max"]:
                return f"axis range {bounds['min']}...{bounds['max']} must have min below max"
    return None


def default_mode(record: dict[str, Any]) -> dict[str, Any]:
    return next(mode for mode in record["modes"] if mode["id"] == "default")


def hex_byte_count(text: str) -> int:
    return len(text.split(" "))


def validate_mode_session(path: pathlib.Path, mode: dict[str, Any]) -> None:
    """The session of one mode obeys the conditionals of that mode's own protocol, as
    `validateSession` in Swift. A HID mode names startup reports, a raw-USB mode startup
    packets, and `interface` selects among HID interfaces, so a raw-USB mode has none."""
    protocol = mode["protocol"]
    family = protocol["family"]
    session = mode.get("session", {})
    startup = session.get("startup", [])
    description = description_of(family)
    if uses_raw_usb(protocol):
        require(
            "interface" not in mode,
            f"{path}: interface selects among HID interfaces; a raw-USB mode claims the "
            "interface its usb transport resolves",
        )
        require(
            all("report" not in write for write in startup),
            f"{path}: HID startup writes apply only to HID controllers, so not to a "
            "raw-USB mode",
        )
        require(
            "keepAlive" not in session or not declares_keep_alive(family),
            f"{path}: a session keepAlive needs a raw-USB family whose description "
            "declares none",
        )
    else:
        for key in ("keepAlive", "settleMilliseconds", "shutdown", "control"):
            require(
                key not in session,
                f"{path}: session {key} applies only to raw-USB modes",
            )
    packets = [write for write in startup if "report" not in write]
    if packets:
        described = description.get("defaults", {}).get("session", {})
        carries = any("report" not in write for write in described.get("startup", []))
        require(
            carries and "initialization" not in protocol,
            f"{path}: raw-USB startup writes need a family that reads them and no "
            "initialization list",
        )
    require(
        "rumble" not in session or reads_record_rumble_template(protocol),
        f"{path}: rumble templates require a driver that encodes them",
    )
    if template := session.get("rumble"):
        problem = protocol_descriptions.rumble_template_problem(template)
        require(problem is None, f"{path}: {problem}")
        if "resendIntervalMilliseconds" in template:
            require(
                "keepAlive" not in session,
                f"{path}: {protocol_descriptions.RESEND_WITH_KEEP_ALIVE}",
            )
            require(
                not declares_keep_alive(protocol["family"]),
                f"{path}: {protocol_descriptions.RESEND_WITH_FAMILY_KEEP_ALIVE}",
            )
        require(
            protocol_descriptions.is_usb_template(template) == uses_raw_usb(protocol),
            f"{path}: a raw-USB mode's rumble template is a usb packet, and a HID mode's is "
            "a HID report",
        )
    for transfer in session.get("control", []):
        outgoing = transfer["bmRequestType"] < 128
        count = hex_byte_count(transfer["data"]) if "data" in transfer else 0
        require(
            not outgoing or count == transfer["wLength"],
            f"{path}: control transfer data has {count} bytes, "
            f"but wLength is {transfer['wLength']}",
        )
        bcd = transfer.get("match", {}).get("bcdDevice")
        require(
            bcd is None or bcd["min"] <= bcd["max"],
            f"{path}: control transfer bcdDevice min must not exceed max",
        )


def validate_initialization(path: pathlib.Path, record: dict[str, Any]) -> None:
    """Every action a mode's protocol names is a named packet of its family, as `ProtocolInfo`
    in Swift."""
    for mode in record["modes"]:
        protocol = mode["protocol"]
        problem = protocol_descriptions.initialization_problem(
            description_of(protocol["family"]), protocol.get("initialization", [])
        )
        require(problem is None, f"{path}: {problem}")


def validate_transport_sections(path: pathlib.Path, record: dict[str, Any]) -> None:
    """The record-level sections that depend on a mode's transport hold for every mode, as
    `validateTransportSections` in Swift."""
    protocols = [mode["protocol"] for mode in record["modes"]]
    raw = [uses_raw_usb(protocol) for protocol in protocols]
    require(
        "usb" not in record or all(raw),
        f"{path}: USB overrides require a raw-USB protocol family",
    )
    require(
        "server" not in record or not any(raw),
        f"{path}: server applies only to HID controllers",
    )
    require(
        "route" not in record or all(raw),
        f"{path}: route ExtensionOwned applies only to raw-USB controllers",
    )
    require(
        "bluetoothLE" not in record
        or all(protocol["family"] == "NintendoSwitch2" for protocol in protocols),
        f"{path}: bluetoothLE requires a Switch 2 controller",
    )
    endpoints = record.get("usb", {}).get("endpoints")
    if endpoints is not None:
        defaults = [
            description_of(protocol["family"])["endpoints"] for protocol in protocols
        ]
        require(
            all(
                (endpoints["in"], endpoints["out"]) != (d["in"], d["out"])
                for d in defaults
            ),
            f"{path}: protocol-default endpoints must be omitted",
        )


def validate_protocol_variants(path: pathlib.Path, record: dict[str, Any]) -> None:
    """Every mode stores a variant exactly when its family's description says records do, and it
    is one of the family's `variants`, as `ProtocolInfo` in Swift."""
    for mode in record["modes"]:
        protocol = mode["protocol"]
        problem = protocol_descriptions.stored_variant_problem(
            protocol["family"], protocol.get("variant")
        )
        require(problem is None, f"{path}: {problem}")


def validate_tuning_scope(path: pathlib.Path, record: dict[str, Any]) -> None:
    """Each `tuning` key is read by the driver of every mode, as `validateTuning` in Swift."""
    for key in record.get("tuning", {}):
        for mode in record["modes"]:
            protocol = mode["protocol"]
            scope = protocol_descriptions.tuning_scope(
                description_of(protocol["family"]), protocol.get("variant")
            )
            require(
                key in scope,
                f"{path}: {key} is not read by the {protocol['family']} driver",
            )


def validate_modes(path: pathlib.Path, record: dict[str, Any]) -> None:
    """The record-level rules every mode obeys, as `validateModes` in Swift."""
    modes = record["modes"]
    identifiers = [mode["id"] for mode in modes]
    require(
        len(set(identifiers)) == len(identifiers),
        f"{path}: mode IDs must be unique: {identifiers}",
    )
    require(
        identifiers.count("default") == 1,
        f"{path}: modes need exactly one mode with the id default: {identifiers}",
    )
    has_layout = "report" in record.get("input", {})
    validate_protocol_variants(path, record)
    validate_transport_sections(path, record)
    validate_tuning_scope(path, record)
    for mode in modes:
        family = mode["protocol"]["family"]
        validate_mode_session(path, mode)
        require(
            "hidUsageMap" not in record.get("input", {}) or family == "HIDDescriptor",
            f"{path}: a HID usage map applies only to HIDDescriptor in every mode",
        )
        require(
            has_layout == requires_record_input_layout(family),
            f"{path}: every mode needs the record's input layout exactly when it is "
            "HIDReportLayout",
        )
        require(
            capabilities_are_declared(record, family),
            f"{path}: capabilities must be deltas the driver of every mode declares",
        )
        match = mode.get("match", {})
        require(
            uses_raw_usb(mode["protocol"])
            or "endpoints" not in match.get("interfaceSignature", {}),
            f"{path}: mode {mode['id']} is a HID mode, whose interfaceSignature has no "
            "endpoints; only the raw USB scanner reads an interface's endpoint set",
        )
        bcd = match.get("bcdDevice")
        require(
            bcd is None or bcd["min"] <= bcd["max"],
            f"{path}: mode {mode['id']} bcdDevice min must not exceed max",
        )
        interface = mode.get("interface")
        require(
            interface is None or interface["first"] <= interface["last"],
            f"{path}: mode {mode['id']} interface first must not exceed last",
        )
        for probe in match.get("probes", []):
            if probe["expect"] == "Bytes":
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
        raise ValidationError(
            f"{path}: invalid JSON: {error}", INVALID_CONTROLLER_RECORD
        ) from error
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


def check_record(
    path: pathlib.Path, record: dict[str, Any], schema_validator: Any
) -> None:
    """Checks one record against the schema and every rule the schema cannot state.

    A failure names its catalog code: E5001 when `apiVersion` is missing or not the supported
    one, E5007 for every other rule.
    """
    check_record_rules(path, record, schema_validator)


def check_record_rules(
    path: pathlib.Path, record: dict[str, Any], schema_validator: Any
) -> None:
    try:
        schema_validator.validate(record)
    except JSONSchemaValidationError as error:
        location = ".".join(str(component) for component in error.absolute_path)
        suffix = f" at {location}" if location else ""
        versioned = list(error.absolute_path) == ["apiVersion"] or (
            error.validator == "required"
            and not error.absolute_path
            and "'apiVersion'" in error.message
        )
        if versioned:
            raise ValidationError(
                f"{path}{suffix}: {error.message}",
                UNSUPPORTED_API_VERSION,
            ) from error
        raise ValidationError(
            f"{path}{suffix}: {error.message}", INVALID_CONTROLLER_RECORD
        ) from error

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

    # JSON Schema cannot express unique mode IDs, probe bytes that fit the read length, the
    # variants and tuning keys a family reads, or the record-level rules each mode obeys; the
    # runtime decoder rejects all of them too.
    validate_modes(path, record)

    # JSON Schema cannot see the description's named packets either.
    validate_initialization(path, record)


def validate_record(
    path: pathlib.Path,
    *,
    enforce_path: bool = True,
    schema_validator: Any | None = None,
) -> tuple[int, int, str]:
    record = load_object(path)
    check_record(path, record, schema_validator or validator())

    vendor_id = record["vendorID"]
    product_id = record["productID"]
    if enforce_path:
        relative = path.relative_to(RECORD_DIR)
        expected = expected_relative_path(vendor_id, product_id)
        require(relative == expected, f"{path}: path must be {expected}")

    return vendor_id, product_id, default_mode(record)["protocol"]["family"]


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
