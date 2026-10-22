"""The family fact that the catalog generator reads from `Resources/Protocols/<file stem>.json`.

`ProtocolDescription` in Swift validates and interprets these files. The generator only reads
`storesVariant`, to know whether a row it builds needs a variant supplied.
"""

from __future__ import annotations

import json
from functools import cache
from pathlib import Path
from typing import Any

PROTOCOLS = Path(__file__).resolve().parents[2] / "Resources" / "Protocols"


@cache
def bundled() -> dict[str, dict[str, Any]]:
    """Every bundled description, by family."""
    descriptions: dict[str, dict[str, Any]] = {}
    for path in sorted(PROTOCOLS.glob("*.json")):
        document = json.loads(path.read_text(encoding="utf-8"))
        descriptions[document["family"]] = document
    return descriptions


def stores_variant(description: dict[str, Any]) -> bool:
    """Whether catalog records store the family's variant."""
    return description.get("storesVariant", False)
