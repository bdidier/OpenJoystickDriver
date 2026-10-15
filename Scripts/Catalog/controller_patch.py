"""The `ControllerPatch` merge: RFC 7396 over layered controller records.

The Swift loader (`ControllerPatchMerge`) implements the same rules. Both read the shared
cases in `Tests/RepositoryScripts/fixtures/controller_patch/cases.json`, so a change to one
side fails the test of the other.

Layer order: catalog record, built-in patch, package patch, user patch. Inside one layer the
selectors apply in the order `all`, `vendorID`/`productID`, `model`, so the more specific
selector wins; a file name and then the owning package name break a tie. A `null` in a patch
deletes the key, and an array replaces the array. An `all` patch sets only the `tuning` keys
that the record's family reads (`tuning_scope`).
"""

from __future__ import annotations

import copy
import re
from typing import Any

from Scripts.Catalog.schema_header import KINDS, header

PATCH_KIND = KINDS["controller-patch"]
LAYERS = ("builtin", "package", "user")
MODEL_PATTERN = re.compile(r"[0-9a-f]{4}-[0-9a-f]{4}\Z")
SECTIONS = frozenset(
    {
        "protocol",
        "usb",
        "bluetoothLE",
        "ownership",
        "route",
        "output",
        "input",
        "tuning",
    }
)
UNSUPPORTED_API_VERSION = "E5001"
RANK_ALL, RANK_IDENTITY, RANK_MODEL = 0, 1, 2
RAW_USB_FAMILIES = frozenset({"xbox.xid", "xbox.xusb", "xbox.gip"})
# The raw values of `PhysicalProtocolID`; a test compares them with the Swift enum.
KNOWN_FAMILIES = frozenset(
    {
        "hid.descriptor",
        "hid.report-layout",
        "xbox.xid",
        "xbox.xusb",
        "xbox.gip",
        "sony.sixaxis",
        "sony.dualshock4",
        "sony.dualsense",
        "nintendo.switch1",
        "nintendo.switch2",
        "nintendo.switch-input-only",
        "valve.steam-controller",
        "valve.steam-triton",
        "valve.steam-deck",
        "vendor.flydigi",
        "vendor.ps3-third-party",
        "vendor.gamesir",
        "vendor.nvidia-shield",
    }
)


class PatchError(ValueError):
    """A patch document that is not a valid `ControllerPatch`.

    `code` is the catalog code, `E5001` when the `apiVersion` is missing or unsupported, and
    None for every other problem, as `DocumentHeaderProblem.code` is in Swift.
    """

    def __init__(self, message: str, code: str | None = None) -> None:
        super().__init__(f"{code}: {message}" if code else message)
        self.code = code


def integer(value: Any) -> int | None:
    """`value` when it is a JSON integer; a bool, a float and a string are not."""
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def record_identity(record: dict[str, Any]) -> tuple[int, int] | None:
    """The `(vendorID, productID)` of `record`, or None when it has no valid pair."""
    vendor_id, product_id = (
        integer(record.get("vendorID")),
        integer(record.get("productID")),
    )
    if vendor_id is None or product_id is None:
        return None
    if not (0 <= vendor_id <= 0xFFFF and 0 <= product_id <= 0xFFFF):
        return None
    return vendor_id, product_id


def model_id(record: dict[str, Any]) -> str:
    """The model id of `record`: until records carry their own, `vvvv-pppp` in lower hex."""
    vendor_id, product_id = int(record["vendorID"]), int(record["productID"])
    return f"{vendor_id:04x}-{product_id:04x}"


def merge_patch(target: Any, patch: Any) -> Any:
    """RFC 7396 `MergePatch`: `null` deletes, an array or scalar replaces."""
    if not isinstance(patch, dict):
        return copy.deepcopy(patch)
    result = dict(target) if isinstance(target, dict) else {}
    for key, value in patch.items():
        if value is None:
            result.pop(key, None)
        else:
            result[key] = merge_patch(result.get(key), value)
    return result


def tuning_scope(record: dict[str, Any]) -> frozenset[str]:
    """The `tuning` keys that a controller of `record`'s family reads.

    `ControllerTuning.scope(ofDocument:)` in Swift is the same rule. A record with no known
    family reads only `stickDeadzone`.
    """
    info = record.get("protocol")
    info = info if isinstance(info, dict) else {}
    family = info.get("family")
    family = family if family in KNOWN_FAMILIES else None
    raw_usb = family in RAW_USB_FAMILIES or (
        family == "vendor.gamesir" and info.get("variant") == "usb"
    )
    scope = {"stickDeadzone"}
    if family == "sony.dualshock4":
        scope.add("inputLivenessTimeoutMs")
    if family == "nintendo.switch1":
        scope |= {"hidStartupRecoveryIntervalMs", "hidStartupRecoveryRounds"}
    if family is not None and not raw_usb:
        scope |= {"hidStartupIntervalMs", "minimumHIDOutputIntervalMs"}
    return frozenset(scope)


def selector_rank(selector: dict[str, Any]) -> int:
    """The rank of `selector`, checked as `ControllerPatch.parse` checks it in Swift."""
    keys = set(selector)
    if keys == {"all"}:
        if selector["all"] is not True:
            raise PatchError("selector.all must be true")
        return RANK_ALL
    if keys == {"vendorID", "productID"}:
        vendor_id, product_id = (
            integer(selector["vendorID"]),
            integer(selector["productID"]),
        )
        if (
            vendor_id is None
            or product_id is None
            or not 1 <= vendor_id <= 0xFFFF
            or not 0 <= product_id <= 0xFFFF
        ):
            raise PatchError("vendorID must be 1...65535 and productID 0...65535")
        return RANK_IDENTITY
    if keys == {"model"}:
        model = selector["model"]
        if not isinstance(model, str) or not MODEL_PATTERN.match(model):
            raise PatchError("selector.model must be vvvv-pppp in lowercase hex")
        return RANK_MODEL
    raise PatchError("selector must be all, model, or vendorID with productID")


def parse_patch(document: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """The checked `(selector, patch)` of a `ControllerPatch` document.

    Every message is the one `ControllerPatch.parse` gives in Swift.
    """
    expected = header(PATCH_KIND)
    if "apiVersion" not in document:
        raise PatchError(
            f"no apiVersion found; the supported apiVersion is {expected['apiVersion']}",
            UNSUPPORTED_API_VERSION,
        )
    if document["apiVersion"] != expected["apiVersion"]:
        raise PatchError(
            f"apiVersion {document['apiVersion']} is not supported; "
            f"the supported apiVersion is {expected['apiVersion']}",
            UNSUPPORTED_API_VERSION,
        )
    if "kind" not in document:
        raise PatchError(f"no kind found; expected {PATCH_KIND}")
    if document["kind"] != PATCH_KIND:
        raise PatchError(f"expected {PATCH_KIND}, found {document['kind']}")
    selector, patch = document.get("selector"), document.get("patch")
    if (
        set(document) != {"apiVersion", "kind", "selector", "patch"}
        or not isinstance(selector, dict)
        or not isinstance(patch, dict)
    ):
        raise PatchError(
            "the file must hold exactly apiVersion, kind, selector, and patch"
        )
    rank = selector_rank(selector)
    if not patch or not set(patch) <= SECTIONS:
        raise PatchError(
            "patch must hold protocol, usb, bluetoothLE, ownership, route, output, "
            "input, or tuning"
        )
    if rank == RANK_ALL and set(patch) != {"tuning"}:
        raise PatchError("an all patch may set only tuning")
    return selector, patch


def selects(selector: dict[str, Any], record: dict[str, Any]) -> bool:
    rank = selector_rank(selector)
    if rank == RANK_ALL:
        return True
    if rank == RANK_MODEL:
        return selector["model"] == model_id(record)
    return (selector["vendorID"], selector["productID"]) == record_identity(record)


def selector_file_name(selector: dict[str, Any]) -> str:
    """The file name a patch with `selector` has in a `Controllers` or `ControllerPatches` folder."""
    rank = selector_rank(selector)
    if rank == RANK_ALL:
        return "all.patch.json"
    if rank == RANK_MODEL:
        return f"model-{selector['model']}.patch.json"
    return (
        f"{int(selector['vendorID']):04x}-{int(selector['productID']):04x}.patch.json"
    )


def ordered(
    patches: list[tuple[dict[str, Any], dict[str, Any], str]],
) -> list[tuple[dict[str, Any], dict[str, Any], str]]:
    """`(selector, body, owner)` entries of one layer, least specific first.

    The order is the selector rank, the file name, the owning package name ("" for a user file),
    and the position, as `ControllerPatchMerge.ordered` in Swift.
    """
    keyed = [
        (selector_rank(item[0]), selector_file_name(item[0]), item[2], index, item)
        for index, item in enumerate(patches)
    ]
    keyed.sort(key=lambda entry: entry[:4])
    return [entry[4] for entry in keyed]


def applied_body(
    selector: dict[str, Any], body: dict[str, Any], record: dict[str, Any]
) -> dict[str, Any] | None:
    """The merge patch that a patch gives to `record`, or None when it changes nothing.

    An `all` patch gives only the `tuning` keys that the record's family reads.
    """
    if selector_rank(selector) != RANK_ALL:
        return body
    scope = tuning_scope(record)
    tuning = body.get("tuning")
    tuning = tuning if isinstance(tuning, dict) else {}
    kept = {key: value for key, value in tuning.items() if key in scope}
    return {"tuning": kept} if kept else None


def apply_patch(
    selector: dict[str, Any], body: dict[str, Any], record: dict[str, Any]
) -> dict[str, Any]:
    """`record` with one patch merged in; `record` itself when the patch gives nothing."""
    given = applied_body(selector, body, record)
    return record if given is None else merge_patch(record, given)


def layer_entries(
    record: dict[str, Any], documents: list[Any]
) -> list[tuple[dict[str, Any], dict[str, Any], str]]:
    """The `(selector, body, owner)` entries of one layer that select `record`, in order.

    A document may be wrapped as `{"owner": name, "document": patch}` to name its package.
    """
    chosen: list[tuple[dict[str, Any], dict[str, Any], str]] = []
    for item in documents:
        owner, document = (
            (item["owner"], item["document"]) if "owner" in item else ("", item)
        )
        selector, patch = parse_patch(document)
        if selects(selector, record):
            chosen.append((selector, patch, owner))
    return ordered(chosen)


def effective_record(
    record: dict[str, Any], layers: dict[str, list[Any]]
) -> dict[str, Any]:
    """`record` with the built-in, package, and user patches applied in that order.

    A record with no valid `vendorID` and `productID` is returned unchanged, as in Swift.
    """
    result = copy.deepcopy(record)
    if record_identity(record) is None:
        return result
    for name in LAYERS:
        for selector, body, _ in layer_entries(result, layers.get(name, [])):
            result = apply_patch(selector, body, result)
    return result
