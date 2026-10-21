from __future__ import annotations

import unittest
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


if __name__ == "__main__":
    unittest.main()
