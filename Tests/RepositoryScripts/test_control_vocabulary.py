from __future__ import annotations

import json
import unittest
from typing import Any

from Scripts.Quality import validate_schemas

VERSION = "openjoystickdriver/v1alpha1"
ROOT = validate_schemas.ROOT
CROSSWALK = ROOT / "Resources" / "Vocabulary" / "crosswalk.json"
SAMPLE_PROFILE = ROOT / "docs" / "sdk" / "sample" / "Profiles" / "sample-pad.json"

# Names the vocabulary replaced. None of them may be a control id any more.
REMOVED_NAMES = [
    "face-south",
    "left-stick-x",
    "left-trigger-button",
    "view",
    "menu",
    "share",
    "options",
    "south",
    "left_stick_x",
    "left_trigger_click",
    "left_grip",
    "mute",
]


class ControlVocabularyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.documents = validate_schemas.validate_schema_documents()
        cls.registry = validate_schemas.schema_registry(cls.documents)
        defs = cls.documents["vocabulary.schema.json"]["$defs"]
        assert isinstance(defs, dict)
        cls.controls: list[str] = defs["control"]["enum"]
        with CROSSWALK.open(encoding="utf-8") as source:
            cls.crosswalk: dict[str, dict[str, Any]] = json.load(source)["controls"]

    def validator(self, name: str) -> Any:
        return validate_schemas.Draft202012Validator(
            self.documents[name],
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        )

    def test_every_id_is_upper_camel_case(self) -> None:
        for control in self.controls:
            self.assertRegex(control, r"^[A-Z][A-Za-z0-9]*$")

    def test_no_removed_name_is_a_control(self) -> None:
        self.assertEqual(set(REMOVED_NAMES) & set(self.controls), set())

    def test_the_crosswalk_has_one_row_per_control(self) -> None:
        self.assertEqual(sorted(self.crosswalk), sorted(self.controls))

    def test_the_crosswalk_round_trips_every_control(self) -> None:
        indexes: dict[str, dict[Any, set[str]]] = {
            "sdl": {},
            "evdev": {},
            "apple": {},
            "hid": {},
            "w3cButton": {},
            "w3cAxis": {},
        }
        for control, row in self.crosswalk.items():
            for column, index in indexes.items():
                if column == "hid":
                    keys: list[Any] = [
                        (entry["page"], entry["usage"])
                        for entry in row["hid"]
                        if entry["usage"]
                    ]
                else:
                    keys = [] if row[column] is None else [row[column]]
                for key in keys:
                    index.setdefault(key, set()).add(control)
        for control, row in self.crosswalk.items():
            for column, index in indexes.items():
                if column == "hid":
                    keys = [(e["page"], e["usage"]) for e in row["hid"] if e["usage"]]
                else:
                    keys = [] if row[column] is None else [row[column]]
                for key in keys:
                    self.assertIn(control, index[key], f"{control} via {column}")
        self.assertEqual(indexes["sdl"]["MISC1"], {"Capture", "Microphone"})
        self.assertEqual(indexes["sdl"]["SOUTH"], {"South"})

    def test_a_profile_with_a_current_name_is_valid(self) -> None:
        with SAMPLE_PROFILE.open(encoding="utf-8") as source:
            profile = json.load(source)
        self.assertTrue(self.validator("profile.schema.json").is_valid(profile))

    def test_a_profile_naming_a_removed_control_is_refused(self) -> None:
        validator = self.validator("profile.schema.json")
        with SAMPLE_PROFILE.open(encoding="utf-8") as source:
            profile = json.load(source)
        for name in REMOVED_NAMES:
            profile["bindings"][0]["source"]["button"] = name
            self.assertFalse(validator.is_valid(profile), name)

    def test_an_endpoint_frame_naming_a_removed_control_is_refused(self) -> None:
        validator = self.validator("endpoint.schema.json")
        frame = {"apiVersion": VERSION, "kind": "Frame", "buttons": ["South"]}
        self.assertTrue(validator.is_valid(frame))
        for name in REMOVED_NAMES:
            self.assertFalse(validator.is_valid({**frame, "buttons": [name]}), name)
            self.assertFalse(validator.is_valid({**frame, "axes": {name: 0.5}}), name)


if __name__ == "__main__":
    unittest.main()
