from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from Scripts.Quality import check_sink_boundary as check


def write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class SinkBoundaryTests(unittest.TestCase):
    def test_no_service_path_calls_a_dispatcher_outside_a_sink(self) -> None:
        self.assertEqual(check.violations(), [])

    def test_planted_bypasses_are_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(
                root,
                "Sources/Service/Route.swift",
                "await output.dispatch(event, labels: labels, from: id)\n"
                "await output.activateOutput(for: id)\n"
                "await manager.setMappingPhysicalOutput(out, active: true, owner: o, for: id)\n"
                "await manager.releaseMappingPhysicalOutputs(for: id)\n"
                "await manager.setProfilePhysicalColor(color, for: id)\n",
            )
            found = check.violations(root)
        self.assertEqual(len(found), 5)

    def test_a_listed_sink_comments_and_declarations_pass(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (forwarder,) = sorted(check.SINK_INTERNALS)[:1]
            write(
                root, forwarder, "await target?.dispatch(event, labels: l, from: id)\n"
            )
            write(
                root,
                "Sources/Kit/Sink.swift",
                "/// Calls `.dispatch(` for the caller.\n"
                "func dispatch(_ event: ControllerEvent) async {}\n"
                "func activateOutput(for id: LogicalControllerID) async {}\n",
            )
            self.assertEqual(check.violations(root), [])


if __name__ == "__main__":
    unittest.main()
