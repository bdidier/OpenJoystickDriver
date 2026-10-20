from __future__ import annotations

import json
import unittest
from pathlib import Path
from typing import Any

from Scripts.Catalog.command_line_name import kebab
from Tests.RepositoryScripts import test_schema_naming

# The samples the Swift `CommandLineNameTests` read too.
SAMPLES = Path(__file__).resolve().parents[1] / "CommandLineNames" / "samples.json"


def samples() -> dict[str, Any]:
    with SAMPLES.open(encoding="utf-8") as source:
        return json.load(source)


class CommandLineNameTests(unittest.TestCase):
    def test_splits_acronym_runs_and_keeps_digits_with_the_word_before(self) -> None:
        for value, expected in samples()["spellings"].items():
            with self.subTest(value=value):
                self.assertEqual(kebab(value), expected)

    def test_is_injective_over_the_sample_values(self) -> None:
        values = samples()["values"]
        self.assertEqual(len({kebab(value) for value in values}), len(values))

    def test_round_trips_every_sample_value_by_lookup(self) -> None:
        values = samples()["values"]
        by_spelling = {kebab(value): value for value in values}
        for value in values:
            self.assertEqual(by_spelling[kebab(value)], value)

    def test_a_value_that_is_not_a_spelling_selects_nothing(self) -> None:
        by_spelling = {kebab(value): value for value in samples()["values"]}
        self.assertNotIn("HIDDescriptor", by_spelling)
        self.assertNotIn("hid_descriptor", by_spelling)

    def test_no_two_values_of_a_schema_enum_share_a_spelling(self) -> None:
        checked = 0
        for schema, document in test_schema_naming.schemas().items():
            groups: dict[str, dict[str, set[str]]] = {}
            for hit in test_schema_naming.checked_strings(document):
                if hit.kind == "value" and hit.pointer.endswith("/enum"):
                    groups.setdefault(hit.pointer, {}).setdefault(
                        kebab(hit.value), set()
                    ).add(hit.value)
            for pointer, spellings in groups.items():
                checked += 1
                for spelling, values in spellings.items():
                    with self.subTest(
                        schema=schema, pointer=pointer, spelling=spelling
                    ):
                        self.assertEqual(len(values), 1, sorted(values))
        self.assertGreater(checked, 100)


if __name__ == "__main__":
    unittest.main()
