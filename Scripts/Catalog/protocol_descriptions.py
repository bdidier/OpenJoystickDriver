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


def record_capabilities_permit(
    description: dict[str, Any], present: set[str], rumble_absent: bool
) -> bool:
    """Whether a record's capability deltas are ones the family's driver acts on.

    `RecordCapabilityRules.permits` in Swift is the same rule.
    """
    rules = description.get("recordCapabilities", {})
    present_ok = not present or present == set(rules.get("present", ()))
    return present_ok and (not rumble_absent or rules.get("rumbleAbsent", False))


def semantic_violations(
    description: dict[str, Any], variants: list[str]
) -> list[tuple[str, str]]:
    """What a schema cannot say about one description, as `ProtocolDescription` rejects in Swift.

    `variants` are the family's variants, which the schema holds per family. Each violation
    is the error code and the message.
    """
    found: list[tuple[str, str]] = []
    raw = description.get("rawUSB")
    if isinstance(raw, list):
        found += [
            ("E5004", f"rawUSB names {variant}, which the family does not have")
            for variant in raw
            if variant not in variants
        ]
    defaults = description.get("defaults", {})
    reads = {
        *ALWAYS_READ,
        *description.get("tuningKeys", ()),
        *description.get("rawUSBTuningKeys", ()),
    }
    unread = sorted(set(defaults.get("tuning", {})) - reads)
    if unread:
        found.append(
            ("E5002", f"defaults.tuning: {', '.join(unread)} not read by the driver")
        )
    for variant, body in defaults.get("variants", {}).items():
        if variant not in variants:
            found.append(
                (
                    "E5004",
                    f"defaults.variants names {variant}, which the family does not have",
                )
            )
            continue
        unread = sorted(set(body["tuning"]) - tuning_scope(description, variant))
        if unread:
            where = f"defaults.variants.{variant}.tuning"
            found.append(
                ("E5002", f"{where}: {', '.join(unread)} not read by the driver")
            )
    found += startup_violations(description, variants)
    found += keep_alive_violations(description, variants)
    return found


def startup_violations(
    description: dict[str, Any], variants: list[str]
) -> list[tuple[str, str]]:
    """The `variants` and `when` of each startup write must name things the family declares."""
    found: list[tuple[str, str]] = []
    parameters = description.get("parameters", {})
    for index, write in enumerate(
        description.get("defaults", {}).get("output", {}).get("startup", [])
    ):
        where = f"defaults.output.startup[{index}]"
        found += [
            ("E5004", f"{where}.variants names {name}, which the family does not have")
            for name in write.get("variants", ())
            if name not in variants
        ]
        when = write.get("when")
        if when is None:
            continue
        declared = parameters.get(when["parameter"], {})
        if declared.get("type") != "enum":
            found.append(
                (
                    "E5002",
                    f"{where}.when: {when['parameter']} is not a declared enumeration",
                )
            )
            continue
        for name in (*when.get("is", ()), *when.get("isNot", ())):
            if name not in declared.get("values", ()):
                found.append(
                    (
                        "E5002",
                        f"{where}.when: {name} is not a value of {when['parameter']}",
                    )
                )
    return found


def keep_alive_violations(
    description: dict[str, Any], variants: list[str]
) -> list[tuple[str, str]]:
    """What `defaults.output.keepAlive` may name, as `ProtocolDescription` checks it in Swift.

    The interval has one home, so tuning must not repeat it; the family must read it; a write
    is a HID report only where the family has HID variants and a raw-USB packet only where it
    has raw-USB ones; a `variants` entry names a variant the family has; and a `resendTuning`
    key is one the family reads and defaults.
    """
    found: list[tuple[str, str]] = []
    defaults = description.get("defaults", {})
    tunings = {"defaults.tuning": defaults.get("tuning", {})} | {
        f"defaults.variants.{variant}.tuning": body["tuning"]
        for variant, body in defaults.get("variants", {}).items()
    }
    found += [
        (
            "E5002",
            f"{where}: keepAliveIntervalMs belongs to defaults.output.keepAlive, not tuning",
        )
        for where, tuning in tunings.items()
        if "keepAliveIntervalMs" in tuning
    ]
    keep_alive = defaults.get("output", {}).get("keepAlive")
    if keep_alive is None:
        return found
    reads = {
        *description.get("tuningKeys", ()),
        *description.get("rawUSBTuningKeys", ()),
    }
    where = "defaults.output.keepAlive"
    if "keepAliveIntervalMs" not in reads:
        found.append(
            (
                "E5002",
                f"{where} applies only to a family that reads keepAliveIntervalMs",
            )
        )
    raw = description.get("rawUSB")
    for index, write in enumerate(keep_alive.get("writes", [])):
        label = f"{where}.writes[{index}]"
        if "report" in write and raw is True:
            found.append(
                ("E5002", f"{label} is a HID write, and the family is raw USB")
            )
        if "report" not in write and not raw:
            found.append(
                (
                    "E5002",
                    f"{label} is a raw-USB write, and the family has no raw-USB variant",
                )
            )
        found += [
            ("E5004", f"{label}.variants names {name}, which the family does not have")
            for name in write.get("variants", ())
            if name not in variants
        ]
        key = write.get("resendTuning")
        if key is not None and (
            key not in reads or key not in defaults.get("tuning", {})
        ):
            found.append(
                (
                    "E5002",
                    f"{label}.resendTuning: {key} must be read by the family and defaulted",
                )
            )
    return found
