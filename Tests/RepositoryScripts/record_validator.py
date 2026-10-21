"""A controller record checked with the schema and every rule the schema cannot state."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from Scripts.Catalog import validate_profiles


class RecordValidator:
    """The schema plus every rule it cannot state, which the description-driven rules
    (variants, tuning scope, capability deltas) need."""

    def __init__(self) -> None:
        self.schema = validate_profiles.validator()

    def is_valid(self, document: dict[str, Any]) -> bool:
        try:
            validate_profiles.check_record(Path("record.json"), document, self.schema)
        except validate_profiles.ValidationError:
            return False
        return True
