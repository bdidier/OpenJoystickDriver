"""The `ControllerPatch` merge: RFC 7396 over layered controller records.

The Swift loader (`ControllerPatchMerge`) implements the same rules. Both read the shared
cases in `Tests/RepositoryScripts/fixtures/controller_patch/cases.json`, so a change to one
side fails the test of the other.

Layer order: catalog record, built-in patch, package patch, user patch. Inside one layer the
selectors apply in the order `all`, `vendorID`/`productID`, `model`, so the more specific
selector wins. A `null` in a patch deletes the key, and an array replaces the array.
"""

from __future__ import annotations

import copy
import re
from typing import Any

from Scripts.Catalog.schema_header import KINDS, header

PATCH_KIND = KINDS["controller-patch"]
LAYERS = ("builtin", "package", "user")
MODEL_PATTERN = re.compile(r"^[0-9a-f]{4}-[0-9a-f]{4}$")
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


class PatchError(ValueError):
    """A patch document that is not a valid `ControllerPatch`.

    `code` is the catalog code, `E5001` when the `apiVersion` is missing or unsupported, and
    None for every other problem, as `DocumentHeaderProblem.code` is in Swift.
    """

    def __init__(self, message: str, code: str | None = None) -> None:
        super().__init__(f"{code}: {message}" if code else message)
        self.code = code


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


def selector_rank(selector: dict[str, Any]) -> int:
    if set(selector) == {"all"} and selector["all"] is True:
        return RANK_ALL
    if set(selector) == {"vendorID", "productID"}:
        return RANK_IDENTITY
    if set(selector) == {"model"}:
        return RANK_MODEL
    raise PatchError(f"invalid selector {selector!r}")


def parse_patch(document: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """The checked `(selector, patch)` of a `ControllerPatch` document."""
    expected = header(PATCH_KIND)
    found = document.get("apiVersion")
    if found != expected["apiVersion"]:
        detail = (
            "no apiVersion found"
            if "apiVersion" not in document
            else (f"apiVersion {found} is not supported")
        )
        raise PatchError(
            f"{detail}; the supported apiVersion is {expected['apiVersion']}",
            UNSUPPORTED_API_VERSION,
        )
    for member, value in expected.items():
        if document.get(member) != value:
            raise PatchError(
                f"{member} must be {value}, found {document.get(member)!r}"
            )
    if set(document) != {"apiVersion", "kind", "selector", "patch"}:
        raise PatchError("invalid patch shape")
    selector, patch = document["selector"], document["patch"]
    if not isinstance(selector, dict) or not isinstance(patch, dict) or not patch:
        raise PatchError("invalid patch shape")
    rank = selector_rank(selector)
    if rank == RANK_MODEL and not MODEL_PATTERN.match(str(selector["model"])):
        raise PatchError(f"invalid model {selector['model']!r}")
    if not set(patch) <= SECTIONS:
        raise PatchError("invalid patch fields")
    if rank == RANK_ALL and set(patch) != {"tuning"}:
        raise PatchError("an `all` patch may set only tuning")
    return selector, patch


def selects(selector: dict[str, Any], record: dict[str, Any]) -> bool:
    rank = selector_rank(selector)
    if rank == RANK_ALL:
        return True
    if rank == RANK_MODEL:
        return selector["model"] == model_id(record)
    return (int(selector["vendorID"]), int(selector["productID"])) == (
        int(record["vendorID"]),
        int(record["productID"]),
    )


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


def layer_patches(
    record: dict[str, Any], documents: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """The patch bodies of one layer that select `record`, least specific first."""
    chosen: list[tuple[int, str, dict[str, Any]]] = []
    for document in documents:
        selector, patch = parse_patch(document)
        if selects(selector, record):
            chosen.append(
                (selector_rank(selector), selector_file_name(selector), patch)
            )
    chosen.sort(key=lambda item: (item[0], item[1]))
    return [patch for _, _, patch in chosen]


def effective_record(
    record: dict[str, Any], layers: dict[str, list[dict[str, Any]]]
) -> dict[str, Any]:
    """`record` with the built-in, package, and user patches applied in that order."""
    result = copy.deepcopy(record)
    for name in LAYERS:
        for patch in layer_patches(result, layers.get(name, [])):
            result = merge_patch(result, patch)
    return result
