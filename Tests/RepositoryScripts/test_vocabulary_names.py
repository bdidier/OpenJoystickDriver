from __future__ import annotations

import copy
import json
import unittest
from typing import Any

from Scripts.Quality import validate_schemas

VERSION = "openjoystickdriver/v1alpha1"
ROOT = validate_schemas.ROOT
SAMPLE_PROFILE = ROOT / "docs" / "sdk" / "sample" / "Profiles" / "sample-pad.json"
UUID = "3B0F9C52-6E1D-4A8B-9C27-5D4E8F1A0B"
UNKNOWN = "notAName"

# Where a profile names a kind, as a path into the profile below.
PROFILE_KINDS: dict[str, tuple[Any, ...]] = {
    "D-pad source direction": ("bindings", 1, "source", "direction"),
    "D-pad destination direction": ("bindings", 2, "destination", "direction"),
    "axis direction": ("bindings", 3, "source", "direction"),
    "keyboard key": ("bindings", 0, "destination", "key"),
    "keyboard modifier": ("bindings", 0, "destination", "modifiers", 0),
    "gyro mode": ("gyroOutput", "mode"),
    "gyro activation": ("gyroOutput", "activationMode"),
    "gyro axes": ("gyroOutput", "trackball", "axes"),
    "Joy-Con gyro selection": ("joyConPair", "gyroSelection"),
    "stick mode": ("stickMappings", 0, "mode"),
    "touch mode": ("touchMappings", 0, "mode"),
}


def profile() -> dict[str, Any]:
    with SAMPLE_PROFILE.open(encoding="utf-8") as source:
        document = json.load(source)
    document["bindings"] = [
        {
            "id": f"{UUID}02",
            "source": {"type": "button", "button": "Start"},
            "destination": {
                "type": "keyboard",
                "key": "KeyJ",
                "modifiers": ["Meta"],
            },
        },
        {
            "id": f"{UUID}03",
            "source": {"type": "dpad", "direction": "DpadUp"},
            "destination": {"type": "mouse_button", "button": "left"},
        },
        {
            "id": f"{UUID}04",
            "source": {"type": "button", "button": "South"},
            "destination": {"type": "gamepad_dpad", "direction": "DpadLeft"},
        },
        {
            "id": f"{UUID}05",
            "source": {
                "type": "axis_direction",
                "axis": "LeftStickX",
                "direction": "Negative",
            },
            "destination": {"type": "gamepad_button", "button": "East"},
        },
    ]
    document["gyroOutput"] = {
        "mode": "Mouse",
        "activationMode": "WhileHeld",
        "activationSource": {"type": "button", "button": "LeftShoulder"},
        "trackball": {
            "axes": "Yaw",
            "source": {"type": "button", "button": "RightShoulder"},
        },
    }
    document["joyConPair"] = {"gyroSelection": "Left"}
    document["stickMappings"] = [{"source": "left", "mode": "FlickOnly"}]
    document["touchMappings"] = [
        {
            "id": f"{UUID}06",
            "surface": "primary",
            "mode": "LeftStick",
            "deadzone": 0.1,
            "pointerSensitivity": 100,
            "stickRadius": 0.5,
        }
    ]
    return document


def replace(document: dict[str, Any], path: tuple[Any, ...], value: Any) -> None:
    node: Any = document
    for step in path[:-1]:
        node = node[step]
    node[path[-1]] = value


class VocabularyNameTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.documents = validate_schemas.validate_schema_documents()
        cls.registry = validate_schemas.schema_registry(cls.documents)

    def validator(self, name: str) -> Any:
        return validate_schemas.Draft202012Validator(
            self.documents[name],
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        )

    def test_a_profile_with_every_vocabulary_name_is_valid(self) -> None:
        errors = list(self.validator("profile.schema.json").iter_errors(profile()))
        self.assertEqual(errors, [])

    def test_every_profile_kind_refuses_an_unknown_name_with_the_invalid_profile_code(
        self,
    ) -> None:
        validator = self.validator("profile.schema.json")
        for kind, path in PROFILE_KINDS.items():
            document = copy.deepcopy(profile())
            replace(document, path, UNKNOWN)
            errors = list(validator.iter_errors(document))
            self.assertTrue(errors, kind)
            for error in errors:
                self.assertEqual(validate_schemas.profile_problem_code(error), "E3008", kind)

    def test_a_profile_with_a_missing_or_unsupported_api_version_has_its_own_code(
        self,
    ) -> None:
        validator = self.validator("profile.schema.json")
        missing = profile()
        del missing["apiVersion"]
        unsupported = {**profile(), "apiVersion": "unsupported.example/v9"}
        for document in (missing, unsupported):
            errors = list(validator.iter_errors(document))
            self.assertTrue(errors)
            self.assertIn(
                "E5001", {validate_schemas.profile_problem_code(e) for e in errors}
            )

    def test_a_profile_of_another_kind_has_the_invalid_profile_code(self) -> None:
        document = {**profile(), "kind": "Controller"}
        errors = list(self.validator("profile.schema.json").iter_errors(document))
        self.assertTrue(errors)
        for error in errors:
            self.assertEqual(validate_schemas.profile_problem_code(error), "E3008")

    def test_a_gyro_activation_that_is_not_always_needs_a_source(self) -> None:
        document = profile()
        del document["gyroOutput"]["activationSource"]
        self.assertFalse(self.validator("profile.schema.json").is_valid(document))
        document["gyroOutput"]["activationMode"] = "Always"
        self.assertTrue(self.validator("profile.schema.json").is_valid(document))

    def test_a_frame_refuses_an_unknown_d_pad_name_with_the_endpoint_code(self) -> None:
        validator = self.validator("endpoint.schema.json")
        frame = {"apiVersion": VERSION, "kind": "Frame", "dpad": ["DpadUp"]}
        self.assertTrue(validator.is_valid(frame))
        self.assertFalse(validator.is_valid({**frame, "dpad": [UNKNOWN]}))
        self.assertEqual(validate_schemas.FRAME_PROBLEM_CODE, "E1003")


if __name__ == "__main__":
    unittest.main()
