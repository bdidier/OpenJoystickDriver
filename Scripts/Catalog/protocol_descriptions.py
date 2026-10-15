"""The family facts that `Resources/Protocols/<family>.json` holds.

`ProtocolDescription` in Swift reads the same files, so a family fact has one home: the
description. This module answers the questions the Python tools ask of it.
"""

from __future__ import annotations

import json
from functools import cache
from pathlib import Path
from typing import Any

PROTOCOLS = Path(__file__).resolve().parents[2] / "Resources" / "Protocols"
ALWAYS_READ = "stickDeadzone"


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

    A controller with no known family reads only `stickDeadzone`; so does a raw-USB one, whose
    driver reads no HID timing. `ControllerTuning.scope(ofDocument:)` in Swift is the same rule.
    """
    scope = {ALWAYS_READ}
    if description is not None and not uses_raw_usb(description, variant):
        scope |= set(description.get("tuningKeys", ()))
    return frozenset(scope)


def tuning_violations(description: dict[str, Any]) -> list[str]:
    """The `defaults.tuning` keys of `description` that its family does not read."""
    tuning = description.get("defaults", {}).get("tuning", {})
    scope = tuning_scope(description, None)
    return sorted(key for key in tuning if key not in scope)
