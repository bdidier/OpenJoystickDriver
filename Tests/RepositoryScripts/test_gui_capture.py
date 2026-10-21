from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from Scripts.Command import dispatcher
from Scripts.GUI import capture


class TargetInvoked(Exception):
    pass


class GuiCaptureTests(unittest.TestCase):
    def test_dispatcher_routes_shots_capture(self) -> None:
        with (
            patch.object(
                dispatcher, "exec_target", side_effect=TargetInvoked
            ) as execute,
            self.assertRaises(TargetInvoked),
        ):
            dispatcher.dispatch(["shots", "capture", "--all"])
        execute.assert_called_once_with("GUI/capture.py", ["--all"], python=True)

    def test_dispatcher_rejects_unknown_shots_command(self) -> None:
        with self.assertRaises(SystemExit):
            dispatcher.dispatch(["shots", "list"])

    def test_area_and_pane_are_exclusive_choices(self) -> None:
        self.assertEqual(capture.parse_args(["--area", "Library"]).area, "Library")
        self.assertEqual(
            capture.parse_args(["--settings-pane", "Advanced"]).settings_pane,
            "Advanced",
        )
        self.assertTrue(capture.parse_args(["--all"]).all)
        for argv in (
            [],
            ["--area", "Library", "--all"],
            ["--area", "Nowhere"],
            ["--settings-pane", "Library"],
        ):
            with self.subTest(argv=argv), self.assertRaises(SystemExit):
                capture.parse_args(argv)

    def test_missing_app_is_reported(self) -> None:
        with (
            patch.object(capture, "APP", capture.PROJECT_DIR / "absent.app"),
            self.assertRaises(capture.CaptureError),
        ):
            capture.process_id()

    def window_id_with(self, bounds: str, windows: list[dict[str, int]]) -> int:
        with (
            patch.object(capture, "gui", return_value=bounds),
            patch.object(capture, "run", return_value=json.dumps(windows)),
        ):
            return capture.window_id(1, "settings")

    def test_window_id_matches_bounds_within_tolerance(self) -> None:
        windows = [
            {"id": 7, "x": 0, "y": 0, "width": 100, "height": 50},
            {"id": 9, "x": 10, "y": 20, "width": 300, "height": 200},
        ]
        self.assertEqual(self.window_id_with("10 20 300 200", windows), 9)
        self.assertEqual(self.window_id_with("11.5 18.5 301 199", windows), 9)

    def test_window_id_rejects_bounds_outside_tolerance(self) -> None:
        windows = [{"id": 9, "x": 10, "y": 20, "width": 300, "height": 200}]
        with self.assertRaises(capture.CaptureError):
            self.window_id_with("13 20 300 200", windows)
        with self.assertRaises(capture.CaptureError):
            self.window_id_with("10 20 300 200", [])

    def test_window_id_rejects_unparsable_bounds(self) -> None:
        with self.assertRaises(capture.CaptureError):
            self.window_id_with("not numbers", [])

    def test_capture_folders_are_unique_within_one_second(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            with patch.object(capture, "PROJECT_DIR", Path(root)):
                first = capture.make_folder()
                second = capture.make_folder()
            self.assertNotEqual(first, second)
            self.assertTrue(first.is_dir() and second.is_dir())

    def test_dispatcher_names_missing_shots_command(self) -> None:
        with (
            patch.object(dispatcher, "die", side_effect=TargetInvoked) as die,
            self.assertRaises(TargetInvoked),
        ):
            dispatcher.dispatch(["shots"])
        die.assert_called_once_with("Unknown: shots (expected: capture)")


if __name__ == "__main__":
    unittest.main()
