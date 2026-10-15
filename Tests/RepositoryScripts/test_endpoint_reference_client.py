from __future__ import annotations

import io
import json
import os
import socket
import tempfile
import threading
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from typing import Any
from unittest.mock import patch

from Scripts.Quality import validate_schemas
from Scripts.SDK import reference_client

VECTOR = Path(__file__).resolve().parent / "fixtures" / "endpoint_hello_proof.json"


class EndpointReferenceClientTests(unittest.TestCase):
    def setUp(self) -> None:
        vector = json.loads(VECTOR.read_text(encoding="utf-8"))
        self.client = {
            "API_VERSION": reference_client.API_VERSION,
            "FRAMES": reference_client.FRAMES,
            "proof": reference_client.proof,
            "play_seconds": reference_client.play_seconds,
            "hello": lambda nonce: reference_client.hello(
                nonce, vector["token"], "driver", "control"
            ),
        }
        documents = validate_schemas.validate_schema_documents()
        registry = validate_schemas.schema_registry(documents)
        endpoint = documents["endpoint.schema.json"]["$id"]

        def validator(name: str) -> validate_schemas.Draft202012Validator:
            return validate_schemas.Draft202012Validator(
                {"$ref": f"{endpoint}#/$defs/{name}"}, registry=registry
            )

        self.client_lines = validator("clientLine")
        self.service_lines = validator("serviceLine")

    def client_environment(self) -> Any:
        token = json.loads(VECTOR.read_text(encoding="utf-8"))["token"]
        return patch.dict(os.environ, {"OJD_TOKEN": token})

    def envelope(self, kind: str, **fields: Any) -> dict[str, Any]:
        return {"apiVersion": self.client["API_VERSION"], "kind": kind, **fields}

    def feed_request(self) -> dict[str, Any]:
        return self.envelope("FeedRequest", **{"as": "Generic"})

    def frame_lines(self) -> list[dict[str, Any]]:
        return [self.envelope("Frame", **frame) for frame in self.client["FRAMES"]]

    def test_proof_matches_the_vector_the_swift_tests_use(self) -> None:
        vector = json.loads(VECTOR.read_text(encoding="utf-8"))
        self.assertEqual((vector["origin"], vector["port"]), ("", ""))
        self.assertEqual(
            self.client["proof"](vector["token"], vector["nonce"]), vector["proof"]
        )

    def test_client_lines_match_the_schema(self) -> None:
        nonce = json.loads(VECTOR.read_text(encoding="utf-8"))["nonce"]
        lines = [
            self.client["hello"](nonce),
            self.feed_request(),
            *self.frame_lines(),
        ]
        for line in lines:
            with self.subTest(line=line):
                self.client_lines.validate(line)

    def test_schema_rejects_a_frame_with_a_repeated_button(self) -> None:
        with self.assertRaises(validate_schemas.ValidationError):
            self.client_lines.validate(
                self.envelope("Frame", buttons=["south", "south"])
            )

    def test_schema_rejects_a_frame_without_the_envelope(self) -> None:
        with self.assertRaises(validate_schemas.ValidationError):
            self.client_lines.validate({"buttons": ["south"]})

    def test_service_lines_match_the_schema(self) -> None:
        lines = [
            self.envelope("FeedSession", **{"as": "Generic"}),
            {
                "apiVersion": self.client["API_VERSION"],
                "kind": "RumbleCommand",
                "type": "setRumble",
                "intensities": {
                    "leftMain": 65535,
                    "rightMain": 0,
                    "leftTrigger": 0,
                    "rightTrigger": 0,
                    "leftHaptic": 0,
                    "rightHaptic": 0,
                },
                "durationMilliseconds": 200,
            },
            self.envelope("RumbleCommand", type="stopRumble"),
            self.envelope("Status", status="Failure", code="E1008", message="Full."),
            self.envelope(
                "Status",
                status="Failure",
                code="E1010",
                message="Unsupported.",
                details={"supportedAPIVersions": [self.client["API_VERSION"]]},
            ),
            {
                "type": "ADDED",
                "object": self.envelope(
                    "Controller",
                    id="pad-1",
                    name="Test Pad",
                    vendorID=1118,
                    productID=654,
                    connection="usb",
                    hasSerialNumber=False,
                    protocol="xbox.xbox360",
                    session="active",
                ),
            },
        ]
        for line in lines:
            with self.subTest(line=line):
                self.service_lines.validate(line)

    def test_client_runs_against_a_fake_endpoint(self) -> None:
        """A fake endpoint, not the service: it checks the client's order of lines."""
        nonce = json.loads(VECTOR.read_text(encoding="utf-8"))["nonce"]
        rumble = self.envelope("RumbleCommand", type="stopRumble")
        received: list[dict[str, Any]] = []
        with tempfile.TemporaryDirectory(dir="/tmp") as directory:
            path = str(Path(directory) / "endpoint.sock")
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(path)
                listener.listen(1)
                listener.settimeout(5)

                def serve() -> None:
                    connection, _ = listener.accept()
                    with connection, connection.makefile("rw") as lines:

                        def send(message: dict[str, Any]) -> None:
                            lines.write(json.dumps(message) + "\n")
                            lines.flush()

                        send(self.envelope("Challenge", nonce=nonce))
                        received.append(json.loads(lines.readline()))
                        send(
                            self.envelope("Welcome", version="test", scopes=["control"])
                        )
                        received.append(json.loads(lines.readline()))
                        send(self.envelope("FeedSession", **{"as": "Generic"}))
                        send(rumble)
                        received.extend(json.loads(line) for line in lines)

                server = threading.Thread(target=serve, daemon=True)
                server.start()
                output = io.StringIO()
                with self.client_environment(), redirect_stdout(output):
                    reference_client.main(["--socket", path, "feed"])
                server.join(timeout=5)

        self.assertFalse(server.is_alive())
        self.assertEqual(received[0], self.client["hello"](nonce))
        self.assertEqual(
            received[1:],
            [self.feed_request(), *self.frame_lines()],
        )
        self.assertEqual(json.loads(output.getvalue()), rumble)

    def run_until_feeding(self, after_feeding: Any) -> SystemExit:
        """Runs the client against a fake endpoint that calls `after_feeding(send)` once the
        client sent `feed`; returns the client's exit."""
        nonce = json.loads(VECTOR.read_text(encoding="utf-8"))["nonce"]
        with tempfile.TemporaryDirectory(dir="/tmp") as directory:
            path = str(Path(directory) / "endpoint.sock")
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(path)
                listener.listen(1)
                listener.settimeout(5)

                def serve() -> None:
                    connection, _ = listener.accept()
                    with connection, connection.makefile("rw") as lines:

                        def send(message: dict[str, Any]) -> None:
                            lines.write(json.dumps(message) + "\n")
                            lines.flush()

                        send(self.envelope("Challenge", nonce=nonce))
                        lines.readline()
                        send(self.envelope("Welcome", version="test", scopes=[]))
                        lines.readline()
                        send(self.envelope("FeedSession", **{"as": "Generic"}))
                        after_feeding(send)

                server = threading.Thread(target=serve, daemon=True)
                server.start()
                with (
                    self.client_environment(),
                    redirect_stdout(io.StringIO()),
                    self.assertRaises(SystemExit) as exit_info,
                ):
                    reference_client.main(["--socket", path, "feed"])
                server.join(timeout=5)
        return exit_info.exception

    def test_client_exits_with_the_error_line_the_endpoint_sends(self) -> None:
        error = self.envelope(
            "Status",
            status="Failure",
            code="E1009",
            message="The virtual gamepad closed.",
        )
        exit_info = self.run_until_feeding(lambda send: send(error))

        self.assertIn("E1009", str(exit_info.code))
        self.assertNotIn(exit_info.code, (0, None))

    def test_client_exits_when_the_endpoint_closes_before_the_release_has_played(
        self,
    ) -> None:
        exit_info = self.run_until_feeding(lambda send: None)

        self.assertIn("closed the connection", str(exit_info.code))

    def test_client_reports_the_supported_versions_on_a_header_error(self) -> None:
        for code in ("E1010", "E1011", "E1012"):
            error = self.envelope(
                "Status",
                status="Failure",
                code=code,
                message="Refused.",
                details={"supportedAPIVersions": ["openjoystickdriver/v1alpha1"]},
            )
            with self.subTest(code=code):
                exit_info = self.run_until_feeding(
                    lambda send, error=error: send(error)
                )

                self.assertIn(code, str(exit_info.code))
                self.assertIn("openjoystickdriver/v1alpha1", str(exit_info.code))
                self.assertIn("Supported apiVersion values", str(exit_info.code))

    def test_client_refuses_a_line_with_another_api_version(self) -> None:
        old = {"apiVersion": "openjoystickdriver.io/v1beta1", "kind": "Challenge"}
        with self.assertRaises(SystemExit) as exit_info:
            reference_client.parse_line(json.dumps(old))

        self.assertIn("openjoystickdriver.io/v1beta1", str(exit_info.exception.code))
        self.assertIn(reference_client.API_VERSION, str(exit_info.exception.code))

    def test_client_checks_the_header_of_a_watch_lines_object(self) -> None:
        controller = {"id": "pad-1", "name": "Test Pad"}
        watch = {"type": "ADDED", "object": self.envelope("Controller", **controller)}
        self.assertEqual(reference_client.parse_line(json.dumps(watch)), watch)

        old = {
            "type": "ADDED",
            "object": {"apiVersion": "other/v1", "kind": "Controller"},
        }
        with self.assertRaises(SystemExit) as exit_info:
            reference_client.parse_line(json.dumps(old))
        self.assertIn("other/v1", str(exit_info.exception.code))

    def test_client_refuses_to_run_without_a_token(self) -> None:
        with (
            patch.dict(os.environ, {}, clear=True),
            self.assertRaises(SystemExit) as exit_info,
        ):
            reference_client.main(["--socket", "/tmp/none.sock", "watch"])
        self.assertIn("OJD_TOKEN", str(exit_info.exception.code))

    def test_client_stays_connected_until_the_last_frame_has_played(self) -> None:
        # The 100 ms press, then the release for the 8 ms minimum.
        self.assertAlmostEqual(
            self.client["play_seconds"](self.client["FRAMES"]), 0.108
        )


if __name__ == "__main__":
    unittest.main()
