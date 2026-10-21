import unittest
from typing import Any, cast

from Scripts.Catalog import schema_header
from Scripts.Quality import validate_schemas

SCHEMA = "cli-output.schema.json"
SESSION = "01234567-89AB-CDEF-0123-456789ABCDEF"


def raw_report(kind: str) -> dict[str, Any]:
    return {
        **schema_header.header(kind),
        "direction": "rx",
        "hex": "01 02",
        "length": 2,
        "captureTime": "1970-01-01T00:00:01.500Z",
    }


def controller_pair(kind: str) -> dict[str, Any]:
    return {
        **schema_header.header(kind),
        "gyro": "Left",
        "left": "switch-1",
        "profile": "pair",
        "right": "switch-2",
        "session": SESSION,
    }


class OutputKindTests(unittest.TestCase):
    def setUp(self) -> None:
        documents = validate_schemas.validate_schema_documents()
        self.schema: dict[str, Any] = documents[SCHEMA]
        self.registry = validate_schemas.schema_registry(documents)

    def validator(self, name: str) -> Any:
        return validate_schemas.Draft202012Validator(
            {"$ref": f"#/$defs/{name}", "$defs": self.schema["$defs"]},
            registry=self.registry,
            format_checker=validate_schemas.FormatChecker(),
        )

    def test_capture_prints_raw_report_lines(self) -> None:
        self.validator("controllerCapture").validate(raw_report("RawReport"))

    def test_pair_and_unpair_print_a_controller_pair(self) -> None:
        for name in ("controllerPair", "controllerUnpair"):
            with self.subTest(name=name):
                self.validator(name).validate(controller_pair("ControllerPair"))

    def test_rejects_an_unknown_kind(self) -> None:
        cases = (
            ("controllerCapture", raw_report, "USBPacket"),
            ("controllerCapture", raw_report, "rawReport"),
            ("controllerPair", controller_pair, "JoyConPair"),
            ("controllerUnpair", controller_pair, "JoyConPair"),
            ("controllerPair", controller_pair, "controllerPair"),
        )
        for name, build, kind in cases:
            with (
                self.subTest(name=name, kind=kind),
                self.assertRaises(validate_schemas.ValidationError),
            ):
                self.validator(name).validate(build(kind))

    def test_rejects_an_unknown_session(self) -> None:
        schema = cast(dict[str, Any], self.schema["$defs"])
        nodes = {
            "controllerList": schema["controllerList"]["properties"]["items"]["items"][
                "properties"
            ]["session"],
            "controllerShow": schema["controllerShow"]["properties"]["session"],
            "sharedControllerSession": schema["sharedControllerSession"]["properties"][
                "session"
            ],
        }
        for name, node in nodes.items():
            checker = validate_schemas.Draft202012Validator(node)
            self.assertTrue(checker.is_valid("Active"), name)
            self.assertTrue(checker.is_valid("Suspended"), name)
            for word in ("active", "suspended", "disconnected", "notAWord"):
                with self.subTest(name=name, word=word):
                    self.assertFalse(checker.is_valid(word))


if __name__ == "__main__":
    unittest.main()
