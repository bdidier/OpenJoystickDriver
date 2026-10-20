"""Rebuild the runtime controller catalog from pinned sources and local overrides."""

from __future__ import annotations

import argparse
import base64
import hashlib
import importlib.util
import json
import pathlib
import re
import shutil
import sys
import tempfile
import urllib.error
import urllib.request
from typing import Any

from Scripts.Catalog import controller_patch
from Scripts.Catalog.catalog_rules import load_rules, parse_id, parse_identity
from Scripts.Catalog.schema_header import KINDS, header
from Scripts.Catalog.xpad_io import json_text, run_gh
from Scripts.Quality.biome_format import format_json

ROOT = pathlib.Path(__file__).resolve().parents[2]
LOCK_PATH = ROOT / "ControllerSources.lock.json"
CONTROLLER_DIR = ROOT / "Resources" / "Controllers"
PATCH_DIR = ROOT / "Resources" / "ControllerPatches"
OUTPUT_DIR = ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
PROTOCOL_DIR = ROOT / "Resources" / "Protocols"
PROTOCOL_OUTPUT_DIR = (
    ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Protocols"
)
VIRTUAL_DEVICE_DIR = ROOT / "Resources" / "VirtualDevices"
VIRTUAL_DEVICE_OUTPUT_DIR = (
    ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "VirtualDevices"
)

# Linux HID records from `Resources/CatalogRules/linux-hid.json`: (source, vendor macro,
# product macro, family, stored variant, parameters, capabilities).
_HID_RULES = load_rules("linux-hid.json", "LinuxHidRules", frozenset({"records"}))
HID_RECORDS: tuple[
    tuple[str, str, str, str, str | None, dict[str, Any], dict[str, Any] | None], ...
] = tuple(
    (
        entry["source"],
        entry["vendorMacro"],
        entry["productMacro"],
        entry["family"],
        entry.get("variant"),
        dict(entry.get("parameters", {})),
        entry.get("capabilities"),
    )
    for entry in _HID_RULES["records"]
)


def load_locked_files(source_lock: dict[str, Any]) -> dict[str, str]:
    result: dict[str, str] = {}
    for key, file_lock in sorted(source_lock["files"].items()):
        url = (
            f"https://raw.githubusercontent.com/{source_lock['repository']}/"
            f"{source_lock['commit']}/{file_lock['path']}"
        )
        request = urllib.request.Request(
            url,
            headers={"User-Agent": "OpenJoystickDriver-catalog"},
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                source = response.read().decode()
        except urllib.error.HTTPError:
            document = json.loads(
                run_gh(
                    [
                        "api",
                        "-X",
                        "GET",
                        f"repos/{source_lock['repository']}/contents/{file_lock['path']}",
                        "-f",
                        f"ref={source_lock['commit']}",
                    ],
                    CatalogError,
                )
            )
            source = base64.b64decode(document["content"]).decode()
        digest = hashlib.sha256(source.encode()).hexdigest()
        if digest != file_lock["sha256"]:
            raise CatalogError(
                f"{key} source hash mismatch: expected {file_lock['sha256']}, got {digest}"
            )
        result[key] = source
    return result


def parse_defines(source: str) -> dict[str, int]:
    return {
        name: int(value, 16)
        for name, value in re.findall(
            r"^#define\s+([A-Z0-9_]+)\s+(0x[0-9a-fA-F]+)\s*$",
            source,
            re.MULTILINE,
        )
    }


def build_hid_records(sources: dict[str, str]) -> list[dict[str, Any]]:
    defines = parse_defines(sources["hid_ids"])
    records: list[dict[str, Any]] = []
    for (
        source_key,
        vendor_macro,
        product_macro,
        family,
        variant,
        parameters,
        capabilities,
    ) in HID_RECORDS:
        source = sources[source_key]
        pattern = (
            r"HID_(?:USB|BLUETOOTH)_DEVICE\s*\(\s*"
            + re.escape(vendor_macro)
            + r"\s*,\s*"
            + re.escape(product_macro)
            + r"\s*\)"
        )
        if re.search(pattern, source) is None:
            raise CatalogError(
                f"{source_key} no longer registers {vendor_macro}/{product_macro}"
            )
        try:
            vendor_id = defines[vendor_macro]
            product_id = defines[product_macro]
        except KeyError as error:
            raise CatalogError(f"missing Linux HID ID definition: {error}") from error
        protocol: dict[str, Any] = {"family": family}
        if variant is not None:
            protocol["variant"] = variant
        if parameters:
            protocol["parameters"] = parameters
        record: dict[str, Any] = {
            **header(KINDS["controller"]),
            "vendorID": vendor_id,
            "productID": product_id,
            "modes": [{"id": "default", "protocol": protocol}],
        }
        if capabilities is not None:
            record["capabilities"] = capabilities
        records.append(record)
    return records


INTERFACE_SIGNATURE_BUCKET = "interface-signature"

# SDL rule tables from `Resources/CatalogRules/sdl.json`. Every identity-keyed table is
# keyed by (vendor ID, product ID).
_SDL_RULES = load_rules(
    "sdl.json",
    "SdlRules",
    frozenset(
        {
            "vendorIDs",
            "microsoftXbox360ProductIDs",
            "controllerTypeFamilies",
            "thirdPartyPS3Family",
            "interfaceSignatureTypes",
            "xboxUsbTypes",
            "identityFamilies",
            "steamVariants",
            "controllerTypeParameters",
            "switch2Identities",
            "bluetoothOnlyIdentities",
            "exclusions",
        }
    ),
)

SONY_VENDOR_ID = parse_id(_SDL_RULES["vendorIDs"]["sony"])
MICROSOFT_VENDOR_ID = parse_id(_SDL_RULES["vendorIDs"]["microsoft"])
NVIDIA_VENDOR_ID = parse_id(_SDL_RULES["vendorIDs"]["nvidia"])
# Microsoft Xbox 360 product IDs; third-party XBoxOneController rows reuse them.
MICROSOFT_XBOX_360_PRODUCT_IDS = frozenset(
    parse_id(text) for text in _SDL_RULES["microsoftXbox360ProductIDs"]
)

# SDL controller type -> (family, stored variant). Types absent here have no implemented
# family and are skipped.
SDL_FAMILIES: dict[str, tuple[str, str | None]] = {
    controller_type: (entry["family"], entry.get("variant"))
    for controller_type, entry in _SDL_RULES["controllerTypeFamilies"].items()
}
# Family of non-Sony PS3Controller rows.
THIRD_PARTY_PS3_FAMILY: str = _SDL_RULES["thirdPartyPS3Family"]

# SDL types whose rows get no record because `ProtocolClassifier` binds them by USB interface
# signature. SDL_XBOX_USB_TYPES adds the types an identity may also be listed under while the
# interface signature still resolves it.
SDL_INTERFACE_SIGNATURE_TYPES = frozenset(_SDL_RULES["interfaceSignatureTypes"])
SDL_XBOX_USB_TYPES = SDL_INTERFACE_SIGNATURE_TYPES | frozenset(
    _SDL_RULES["xboxUsbTypes"]
)

# Identities whose SDL driver differs from the one their SDL type implies:
# (identity) -> (expected SDL type, family, stored variant). Each entry must still be
# listed with that type at the pinned commit.
SDL_IDENTITY_FAMILIES: dict[tuple[int, int], tuple[str, str, str | None]] = {
    parse_identity(entry["identity"]): (
        entry["sdlType"],
        entry["family"],
        entry.get("variant"),
    )
    for entry in _SDL_RULES["identityFamilies"]
}

# Stored variant of each Steam Controller and Steam Triton identity. A row of either family
# missing here fails generation instead of guessing.
STEAM_VARIANTS: dict[tuple[int, int], str] = {
    parse_identity(entry["identity"]): entry["variant"]
    for entry in _SDL_RULES["steamVariants"]
}

# SDL controller type -> protocol parameters its rows carry.
SDL_PARAMETERS: dict[str, dict[str, Any]] = {
    controller_type: dict(parameters)
    for controller_type, parameters in _SDL_RULES["controllerTypeParameters"].items()
}

# Nintendo Switch 2 identities; their rows select the Switch 2 protocol whatever their SDL type.
SWITCH_2_IDENTITIES = frozenset(
    parse_identity(text) for text in _SDL_RULES["switch2Identities"]
)
SWITCH_2_FAMILY = "NintendoSwitch2"
# Families whose SDL rows take their stored variant from STEAM_VARIANTS.
STEAM_VARIANT_FAMILIES = frozenset({"ValveSteamController", "ValveSteamTriton"})

# Identities that get no record: (identity) -> (expected SDL type, skip reason). Each entry
# must still be listed with that type at the pinned commit and must not already be catalogued.
# A reason of `interface-signature` means the XUSB or GIP interface signature binds the pad.
SDL_EXCLUSIONS: dict[tuple[int, int], tuple[str, str]] = {
    parse_identity(entry["identity"]): (entry["sdlType"], entry["reason"])
    for entry in _SDL_RULES["exclusions"]
}

# Switch pads whose USB link only charges them.
BLUETOOTH_ONLY_IDENTITIES = frozenset(
    parse_identity(text) for text in _SDL_RULES["bluetoothOnlyIdentities"]
)

SDL_ARRAY_PATTERN = re.compile(
    r"arrControllers\[\]\s*=\s*\{(?P<body>.*?)^\};", re.DOTALL | re.MULTILINE
)
SDL_ENTRY_PATTERN = re.compile(
    r"""
    \{\s*MAKE_CONTROLLER_ID\s*\(\s*
    (?P<vid>0[xX][0-9a-fA-F]+)\s*,\s*
    (?P<pid>0[xX][0-9a-fA-F]+)\s*\)\s*,\s*
    k_eControllerType_(?P<type>\w+)\s*,\s*
    (?:NULL|"(?:\\.|[^"\\])*")\s*
    \}\s*,\s*(?://.*)?
    """,
    re.VERBOSE,
)


def parse_sdl_controllers(source: str) -> list[tuple[int, int, str]]:
    """Returns (vendor ID, product ID, SDL type) for every active arrControllers row."""
    match = SDL_ARRAY_PATTERN.search(source)
    if match is None:
        raise CatalogError("SDL controller_list.h has no arrControllers table")
    rows: list[tuple[int, int, str]] = []
    for line in match["body"].splitlines():
        text = line.strip()
        if not text or text.startswith("//"):
            continue
        entry = SDL_ENTRY_PATTERN.fullmatch(text)
        if entry is None:
            raise CatalogError(f"unparsed SDL controller_list.h row: {text}")
        rows.append((int(entry["vid"], 16), int(entry["pid"], 16), entry["type"]))
    if not rows:
        raise CatalogError("SDL controller_list.h produced no rows")
    return rows


def sdl_rule_reason(key: tuple[int, int], controller_type: str) -> str | None:
    vendor_id, product_id = key
    if vendor_id == 0:
        return "not-usb-identity"
    if (
        controller_type == "XBoxOneController"
        and product_id in MICROSOFT_XBOX_360_PRODUCT_IDS
    ):
        # The ID says XUSB, the SDL type says GIP; the interface signature decides.
        return INTERFACE_SIGNATURE_BUCKET
    return None


def sdl_family(
    key: tuple[int, int], controller_type: str
) -> tuple[str, str | None] | None:
    """Returns (family, stored variant) for an SDL row, or None for an unmapped type."""
    override = SDL_IDENTITY_FAMILIES.get(key)
    if override is not None:
        return override[1], override[2]
    if key in SWITCH_2_IDENTITIES:
        return SWITCH_2_FAMILY, None
    if controller_type == "PS3Controller" and key[0] != SONY_VENDOR_ID:
        return THIRD_PARTY_PS3_FAMILY, None
    return SDL_FAMILIES.get(controller_type)


def sdl_skip_reason(key: tuple[int, int], controller_type: str) -> str | None:
    rule = sdl_rule_reason(key, controller_type)
    exclusion = SDL_EXCLUSIONS.get(key)
    if exclusion is not None:
        if rule is not None:
            raise CatalogError(f"redundant SDL exclusion {key}: rule {rule} applies")
        return exclusion[1]
    if (
        rule is None
        and key not in SDL_IDENTITY_FAMILIES
        and key[0] == MICROSOFT_VENDOR_ID
        and (controller_type == "XBoxOneController")
    ):
        # Microsoft ships Bluetooth and Windows-driver identities under this type;
        # a new one must be reviewed before it can bind the USB-only GIP driver.
        raise CatalogError(f"unreviewed Microsoft SDL XBoxOneController row {key}")
    if rule is None and key not in SDL_IDENTITY_FAMILIES and key[0] == NVIDIA_VENDOR_ID:
        # SDL drives NVIDIA pads with `SDL_hidapi_shield.c`, not the protocol their SDL type
        # names; a new one must be reviewed before it can bind another driver.
        raise CatalogError(f"unreviewed NVIDIA SDL row {key}")
    return rule


def build_sdl_records(
    rows: list[tuple[int, int, str]],
    existing: dict[tuple[int, int], str],
) -> tuple[dict[tuple[int, int], dict[str, Any]], dict[str, int]]:
    """Admits SDL identities absent from `existing` (identity -> family).

    Every distinct identity lands in exactly one count bucket, independent of row order.
    """
    types: dict[tuple[int, int], set[str]] = {}
    for vendor_id, product_id, controller_type in rows:
        types.setdefault((vendor_id, product_id), set()).add(controller_type)

    for key, (expected_type, _) in sorted(SDL_EXCLUSIONS.items()):
        if expected_type not in types.get(key, set()):
            raise CatalogError(
                f"stale SDL exclusion {key}: not listed as {expected_type}"
            )
    for key, (expected_type, _, _) in sorted(SDL_IDENTITY_FAMILIES.items()):
        if expected_type not in types.get(key, set()):
            raise CatalogError(
                f"stale SDL identity family {key}: not listed as {expected_type}"
            )

    records: dict[tuple[int, int], dict[str, Any]] = {}
    counts: dict[str, int] = {}

    def count(bucket: str) -> None:
        counts[bucket] = counts.get(bucket, 0) + 1

    for key in sorted(types):
        if len(types[key]) > 1:
            signature_bound = key not in existing and types[key] <= SDL_XBOX_USB_TYPES
            count(INTERFACE_SIGNATURE_BUCKET if signature_bound else "sdl-conflict")
            continue
        (controller_type,) = types[key]
        if controller_type in SDL_INTERFACE_SIGNATURE_TYPES:
            count(INTERFACE_SIGNATURE_BUCKET)
            continue
        mapping = sdl_family(key, controller_type)
        if mapping is None:
            reason = sdl_skip_reason(key, controller_type)
            count(
                f"unmapped:{controller_type}"
                if reason is None
                else reason
                if reason == INTERFACE_SIGNATURE_BUCKET
                else f"excluded:{reason}"
            )
            continue
        family, variant = mapping
        if key in existing:
            if key in SDL_EXCLUSIONS:
                raise CatalogError(f"redundant SDL exclusion {key}: already catalogued")
            count("duplicate" if existing[key] == family else "conflict")
            continue
        reason = sdl_skip_reason(key, controller_type)
        if reason is not None:
            count(
                reason if reason == INTERFACE_SIGNATURE_BUCKET else f"excluded:{reason}"
            )
            continue
        if family in STEAM_VARIANT_FAMILIES:
            if key not in STEAM_VARIANTS:
                raise CatalogError(f"Steam row {key} has no STEAM_VARIANTS entry")
            variant = STEAM_VARIANTS[key]
        protocol: dict[str, Any] = {"family": family}
        if variant is not None:
            protocol["variant"] = variant
        parameters: dict[str, Any] = {}
        if key in BLUETOOTH_ONLY_IDENTITIES:
            parameters["usbProtocol"] = "ChargingOnly"
        parameters.update(SDL_PARAMETERS.get(controller_type, {}))
        # SDL runs a non-Sony PS5Controller through its third-party DualSense path.
        if family == "SonyDualSense" and key[0] != SONY_VENDOR_ID:
            parameters["maker"] = "ThirdParty"
        if parameters:
            protocol["parameters"] = parameters
        vendor_id, product_id = key
        records[key] = {
            **header(KINDS["controller"]),
            "vendorID": vendor_id,
            "productID": product_id,
            "modes": [{"id": "default", "protocol": protocol}],
        }
        count("added")
    return records, counts


class CatalogError(RuntimeError):
    pass


def load_module(name: str, path: pathlib.Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise CatalogError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def record_key(record: dict[str, Any]) -> tuple[int, int]:
    return int(record["vendorID"]), int(record["productID"])


def record_path(root: pathlib.Path, key: tuple[int, int]) -> pathlib.Path:
    vendor_id, product_id = key
    return root / f"{vendor_id:04x}" / f"{vendor_id:04x}-{product_id:04x}.json"


def load_lock() -> dict[str, Any]:
    try:
        lock = json.loads(LOCK_PATH.read_text())
        linux = lock["linux"]
        xpad = linux["files"]["xpad"]
        if linux["repository"] != "torvalds/linux":
            raise CatalogError("unsupported Linux repository")
        if len(linux["commit"]) != 40:
            raise CatalogError("Linux commit must be a full SHA")
        if len(xpad["sha256"]) != 64:
            raise CatalogError("xpad SHA-256 is invalid")
        sdl = lock["sdl"]
        if sdl["repository"] != "libsdl-org/SDL":
            raise CatalogError("unsupported SDL repository")
        if len(sdl["commit"]) != 40:
            raise CatalogError("SDL commit must be a full SHA")
        if len(sdl["files"]["controller_list"]["sha256"]) != 64:
            raise CatalogError("SDL controller_list SHA-256 is invalid")
        return lock
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise CatalogError(f"invalid {LOCK_PATH.name}: {error}") from error


def patch_path(root: pathlib.Path, selector: dict[str, Any]) -> pathlib.Path:
    """Where the built-in patch with `selector` is stored under `root`."""
    name = controller_patch.selector_file_name(selector)
    if "vendorID" in selector:
        return root / f"{int(selector['vendorID']):04x}" / name
    return root / name


def load_authored(
    validator: Any,
    controller_dir: pathlib.Path = CONTROLLER_DIR,
    patch_dir: pathlib.Path = PATCH_DIR,
) -> tuple[
    dict[tuple[int, int], dict[str, Any]],
    list[tuple[dict[str, Any], dict[str, Any]]],
]:
    """The authored `Controller` records and the built-in `ControllerPatch` bodies."""
    adds: dict[tuple[int, int], dict[str, Any]] = {}
    for path in sorted(controller_dir.glob("*/*.json")):
        record = json.loads(path.read_text())
        if validator is not None:
            validator.validate_record(path, enforce_path=False)
        key = record_key(record)
        expected = record_path(controller_dir, key)
        if path != expected:
            raise CatalogError(f"{path}: controller path must be {expected}")
        adds[key] = record
    patches: list[tuple[dict[str, Any], dict[str, Any]]] = []
    for path in sorted([*patch_dir.glob("*.json"), *patch_dir.glob("*/*.json")]):
        try:
            selector, body = controller_patch.parse_patch(json.loads(path.read_text()))
        except controller_patch.PatchError as error:
            raise CatalogError(f"{path}: {error}") from error
        expected = patch_path(patch_dir, selector)
        if path != expected:
            raise CatalogError(f"{path}: patch path must be {expected}")
        patches.append((selector, body))
    return adds, patches


def apply_patches(
    records: dict[tuple[int, int], dict[str, Any]],
    adds: dict[tuple[int, int], dict[str, Any]],
    patches: list[tuple[dict[str, Any], dict[str, Any]]],
) -> None:
    """Adds the authored records, then applies the built-in layer to every record."""
    for key, record in adds.items():
        if key in records:
            raise CatalogError(f"controller conflicts with upstream identity {key}")
        records[key] = record
    known = {controller_patch.model_id(record) for record in records.values()}
    for selector, _ in patches:
        if "all" in selector:
            continue
        target = selector.get("model") or "{:04x}-{:04x}".format(
            int(selector["vendorID"]), int(selector["productID"])
        )
        if target not in known:
            raise CatalogError(f"orphan patch for {target}")
    for key, record in list(records.items()):
        merged = record
        chosen = controller_patch.ordered(
            [
                (selector, body, "")
                for selector, body in patches
                if controller_patch.selects(selector, record)
            ]
        )
        for selector, body, _ in chosen:
            after = controller_patch.apply_patch(selector, body, merged)
            if after == merged and "all" not in selector:
                raise CatalogError(f"redundant patch for {key}")
            merged = after
        records[key] = merged


def merge_sdl_records(
    records: dict[tuple[int, int], dict[str, Any]],
    adds: dict[tuple[int, int], dict[str, Any]],
    rows: list[tuple[int, int, str]],
) -> dict[str, int]:
    """Adds SDL identities to Linux `records`; Linux rows and authored controllers win."""
    existing = {
        key: controller_patch.default_protocol(record)["family"]
        for key, record in records.items()
    }
    for key, record in adds.items():
        existing[key] = controller_patch.default_protocol(record)["family"]
    sdl_records, counts = build_sdl_records(rows, existing)
    records.update(sdl_records)
    return counts


def build_catalog() -> dict[tuple[int, int], dict[str, Any]]:
    generator = load_module(
        "ojd_generate_xpad_records",
        ROOT / "Scripts" / "Catalog" / "generate_xpad_records.py",
    )
    validator = load_module(
        "ojd_validate_profiles",
        ROOT / "Scripts" / "Catalog" / "validate_profiles.py",
    )
    lock = load_lock()
    linux = lock["linux"]

    sources = load_locked_files(linux)
    source = sources["xpad"]
    candidates, skipped, _ = generator.generate_candidates(
        devices=generator.parse_devices(source),
        init_rules=generator.parse_init_rules(source),
        existing_keys=set(),
        include_existing=True,
        requested_type="all",
        vendor_id=None,
        product_id=None,
    )
    records: dict[tuple[int, int], dict[str, Any]] = {}
    for candidate in candidates:
        key = (candidate.device.vendor_id, candidate.device.product_id)
        if key in records:
            raise CatalogError(f"Linux source produced duplicate identity {key}")
        records[key] = candidate.profile
    for record in build_hid_records(sources):
        key = record_key(record)
        if key in records:
            raise CatalogError(f"Linux sources produced duplicate identity {key}")
        records[key] = record

    adds, patches = load_authored(validator)
    sdl_rows = parse_sdl_controllers(load_locked_files(lock["sdl"])["controller_list"])
    sdl_counts = merge_sdl_records(records, adds, sdl_rows)
    apply_patches(records, adds, patches)

    if not records:
        raise CatalogError("generation produced no controller records")

    with tempfile.TemporaryDirectory() as directory:
        temporary_root = pathlib.Path(directory)
        for key, record in sorted(records.items()):
            path = record_path(temporary_root, key)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json_text(record))
            validator.validate_record(path, enforce_path=False)

    if skipped:
        print(f"Linux rows intentionally skipped: {len(skipped)}")
    print(sdl_summary(sdl_rows, sdl_counts))
    return records


def sdl_summary(rows: list[tuple[int, int, str]], counts: dict[str, int]) -> str:
    unmapped = sum(
        value
        for bucket, value in counts.items()
        if bucket.startswith("unmapped:") or bucket == "sdl-conflict"
    )
    identities = sum(counts.values())
    lines = [
        (
            f"SDL rows parsed: {len(rows)} ({identities} identities); "
            f"mapped {identities - unmapped}, added {counts.get('added', 0)}, "
            f"duplicates {counts.get('duplicate', 0)}, "
            f"conflicts {counts.get('conflict', 0)}, "
            f"bound by interface signature {counts.get(INTERFACE_SIGNATURE_BUCKET, 0)}"
        ),
        *(
            f"  skipped {bucket}: {value}"
            for bucket, value in sorted(counts.items())
            if bucket
            not in {"added", "duplicate", "conflict", INTERFACE_SIGNATURE_BUCKET}
        ),
    ]
    return "\n".join(lines)


def expected_files(
    records: dict[tuple[int, int], dict[str, Any]],
) -> dict[pathlib.Path, str]:
    files = format_json(
        {
            record_path(OUTPUT_DIR, key): json_text(record)
            for key, record in sorted(records.items())
        }
    )
    # The bundle ships the authored protocol descriptions unchanged.
    for path in sorted(PROTOCOL_DIR.glob("*.json")):
        files[PROTOCOL_OUTPUT_DIR / path.name] = path.read_text()
    # It ships the authored virtual device records unchanged.
    for path in sorted(VIRTUAL_DEVICE_DIR.glob("*.json")):
        files[VIRTUAL_DEVICE_OUTPUT_DIR / path.name] = path.read_text()
    return files


def check_catalog(records: dict[tuple[int, int], dict[str, Any]]) -> None:
    expected = expected_files(records)
    actual = {
        *OUTPUT_DIR.glob("*/*.json"),
        *PROTOCOL_OUTPUT_DIR.glob("*.json"),
        *VIRTUAL_DEVICE_OUTPUT_DIR.glob("*.json"),
    }
    missing = sorted(set(expected) - actual)
    stale = sorted(actual - set(expected))
    changed = sorted(
        path
        for path, text in expected.items()
        if path.exists() and path.read_text() != text
    )
    if missing or stale or changed:
        details = [
            *(f"missing {path.relative_to(ROOT)}" for path in missing),
            *(f"stale {path.relative_to(ROOT)}" for path in stale),
            *(f"changed {path.relative_to(ROOT)}" for path in changed),
        ]
        raise CatalogError(
            "catalog differs from generated output:\n" + "\n".join(details)
        )


def write_catalog(records: dict[tuple[int, int], dict[str, Any]]) -> None:
    expected = expected_files(records)
    for directory in (OUTPUT_DIR, PROTOCOL_OUTPUT_DIR, VIRTUAL_DEVICE_OUTPUT_DIR):
        if directory.exists():
            shutil.rmtree(directory)
    for path, text in expected.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


def main() -> int:
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true")
    action.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        records = build_catalog()
        if args.check:
            check_catalog(records)
            verb = "Verified"
        else:
            write_catalog(records)
            verb = "Generated"
    except (CatalogError, OSError, KeyError, TypeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"{verb} {len(records)} canonical controller record(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
