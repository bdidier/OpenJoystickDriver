"""The family facts that `Resources/Protocols/<file stem>.json` holds.

`ProtocolDescription` in Swift reads the same files, so a family fact has one home: the
description. This module answers the questions the Python tools ask of it.
"""

from __future__ import annotations

import json
from functools import cache
from pathlib import Path
from typing import Any

PROTOCOLS = Path(__file__).resolve().parents[2] / "Resources" / "Protocols"
ALWAYS_READ = frozenset({"stickDeadzone", "frameQueueCapacity"})


@cache
def bundled() -> dict[str, dict[str, Any]]:
    """Every bundled description, by family."""
    descriptions: dict[str, dict[str, Any]] = {}
    for path in sorted(PROTOCOLS.glob("*.json")):
        document = json.loads(path.read_text(encoding="utf-8"))
        descriptions[document["family"]] = document
    return descriptions


def uses_raw_usb(description: dict[str, Any], variant: str | None) -> bool:
    """Whether rows of the family, with this stored variant, are reached through raw USB.

    `rawUSB` is `true` for every variant, or the variants that are; absent means HID.
    """
    raw = description.get("rawUSB")
    if isinstance(raw, list):
        return variant in raw
    return raw is True


def tuning_scope(
    description: dict[str, Any] | None, variant: str | None
) -> frozenset[str]:
    """The `tuning` keys a controller of this family and variant reads.

    A controller with no known family reads only `stickDeadzone` and `frameQueueCapacity`. A raw-USB variant reads
    `rawUSBTuningKeys` and no HID timing; every other variant reads `tuningKeys`.
    `ProtocolDescription.tuningScope(variant:)` in Swift is the same rule.
    """
    scope = set(ALWAYS_READ)
    if description is not None:
        key = "rawUSBTuningKeys" if uses_raw_usb(description, variant) else "tuningKeys"
        scope |= set(description.get(key, ()))
    return frozenset(scope)


def family_variants(description: dict[str, Any]) -> list[str]:
    """The variants of the family, as its description lists them; none when it has one contract.

    `ProtocolDescription.variants` in Swift is the same list.
    """
    return list(description.get("variants", ()))


def stores_variant(description: dict[str, Any]) -> bool:
    """Whether catalog records store the family's variant.

    `ProtocolDescription.storesVariant` in Swift is the same fact.
    """
    return description.get("storesVariant", False)


def stored_variant_problem(family: str, variant: str | None) -> str | None:
    """Why `variant` is not what a record of `family` stores, or None.

    A record stores a variant exactly when the family's description says records do, and it is
    one of the family's `variants`.
    """
    description = bundled().get(family)
    if description is None:
        return f"{family} has no description"
    if stores_variant(description) != (variant is not None) or (
        variant is not None and variant not in family_variants(description)
    ):
        return f"variant must be a stored variant of family {family}"
    return None
