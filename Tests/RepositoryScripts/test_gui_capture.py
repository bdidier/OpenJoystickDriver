from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from datetime import datetime
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

    def test_dispatcher_names_missing_shots_command(self) -> None:
        with (
            patch.object(dispatcher, "die", side_effect=TargetInvoked) as die,
            self.assertRaises(TargetInvoked),
        ):
            dispatcher.dispatch(["shots"])
        die.assert_called_once_with("Unknown: shots (expected: capture)")

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

    def test_window_id_rejects_wrong_number_of_bounds(self) -> None:
        for reported in ("1 2 3", "1 2 3 4 5", ""):
            with (
                self.subTest(reported=reported),
                self.assertRaises(capture.CaptureError),
            ):
                self.window_id_with(reported, [])

    def test_capture_folders_are_unique_within_one_second(self) -> None:
        with (
            tempfile.TemporaryDirectory() as root,
            patch.object(capture, "PROJECT_DIR", Path(root)),
            patch.object(capture, "datetime") as clock,
        ):
            clock.now.return_value = datetime(2026, 1, 2, 3, 4, 5)
            names = [capture.make_folder().name for _ in range(3)]
        self.assertEqual(
            names, ["20260102-030405", "20260102-030405-1", "20260102-030405-2"]
        )

    def run_capture(
        self,
        state: tuple[bool, str | None],
        failures: dict[str, Exception],
        argv: list[str],
    ) -> tuple[int | None, list[tuple[str, ...]], Exception | None]:
        calls: list[tuple[str, ...]] = []

        def fake_gui(*command: str) -> str:
            calls.append(command)
            if command[0] in failures:
                raise failures[command[0]]
            return "Activity" if command[0] == "current-sidebar.applescript" else ""

        with (
            tempfile.TemporaryDirectory() as root,
            patch.object(capture, "PROJECT_DIR", Path(root)),
            patch.object(capture, "process_id", return_value=1),
            patch.object(capture, "require_accessibility"),
            patch.object(capture, "require_english_ui"),
            patch.object(capture, "read_state", return_value=state),
            patch.object(capture, "gui", side_effect=fake_gui),
            patch.object(capture, "shoot"),
            patch.object(capture.sys, "stderr"),
        ):
            try:
                code = capture.capture(capture.parse_args(argv))
            except capture.CaptureError as error:
                return None, calls, error
            return code, calls, None

    def test_restore_closes_what_the_run_opened(self) -> None:
        code, calls, error = self.run_capture(
            (False, None), {}, ["--settings-pane", "Advanced"]
        )
        self.assertEqual((code, error), (0, None))
        self.assertEqual(
            calls[-3:],
            [
                ("select-sidebar.applescript", "Activity"),
                ("close-window.applescript", "settings"),
                ("close-window.applescript", "main"),
            ],
        )

    def test_restore_keeps_windows_and_tab_that_were_open(self) -> None:
        code, calls, error = self.run_capture(
            (True, "General"), {}, ["--settings-pane", "Advanced"]
        )
        self.assertEqual((code, error), (0, None))
        self.assertEqual(
            calls[-2:],
            [
                ("select-sidebar.applescript", "Activity"),
                ("open-settings.applescript", "General"),
            ],
        )
        self.assertNotIn(("close-window.applescript", "main"), calls)

    def test_failed_capture_keeps_its_error_and_still_restores(self) -> None:
        failures: dict[str, Exception] = {
            "open-settings.applescript": capture.CaptureError("menu failed"),
            "close-window.applescript": capture.CaptureError("no window"),
        }
        code, calls, error = self.run_capture(
            (False, None), failures, ["--settings-pane", "General"]
        )
        self.assertIsNone(code)
        self.assertEqual(str(error), "menu failed")
        self.assertEqual(calls[-3][0], "select-sidebar.applescript")
        self.assertEqual(calls[-1], ("close-window.applescript", "main"))

    def test_failed_restore_step_does_not_skip_later_steps(self) -> None:
        failures: dict[str, Exception] = {
            "select-sidebar.applescript": capture.CaptureError("row missing")
        }
        code, calls, error = self.run_capture(
            (False, None), failures, ["--settings-pane", "General"]
        )
        self.assertEqual((code, error), (2, None))
        self.assertEqual(calls[-1], ("close-window.applescript", "main"))

    def completed(self, code: int, out: str) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess([], code, out, "")

    def test_accessibility_probe_granted_lets_capture_continue(self) -> None:
        with patch.object(capture, "run", return_value="0") as probe:
            capture.require_accessibility()
        self.assertIn("accessibility-probe.js", probe.call_args.args[0][-1])

    def test_accessibility_probe_denied_fails_before_any_gui_script(self) -> None:
        with (
            patch.object(capture, "run", return_value="-25211"),
            patch.object(capture, "gui") as gui,
            patch.object(capture, "process_id") as pid,
            self.assertRaises(capture.CaptureError) as raised,
        ):
            capture.capture(capture.parse_args(["--area", "Controllers"]))
        message = str(raised.exception)
        self.assertIn(capture.ACCESSIBILITY_MISSING, message)
        self.assertIn("-25211", message)
        self.assertIn("Privacy & Security > Accessibility", message)
        self.assertIn("cannot run without it", message)
        gui.assert_not_called()
        pid.assert_not_called()

    def test_english_ui_is_required(self) -> None:
        english = self.completed(0, '(\n    "en-US",\n    "et-EE"\n)')
        german = self.completed(0, '(\n    "de-DE",\n    "en-US"\n)')
        unset = self.completed(1, "")
        with patch.object(capture.subprocess, "run", side_effect=[unset, english]):
            capture.require_english_ui()
        with (
            patch.object(capture.subprocess, "run", side_effect=[german]),
            self.assertRaisesRegex(capture.CaptureError, "de-DE"),
        ):
            capture.require_english_ui()
        with (
            patch.object(capture.subprocess, "run", side_effect=[unset, unset]),
            self.assertRaises(capture.CaptureError),
        ):
            capture.require_english_ui()

    def test_read_state_parses_and_validates(self) -> None:
        for reported, expected in (
            ("main=true settings=none", (True, None)),
            ("main=false settings=Advanced", (False, "Advanced")),
        ):
            with patch.object(capture, "gui", return_value=reported):
                self.assertEqual(capture.read_state(), expected)
        for reported in ("garbage", "main=true settings=Elsewhere"):
            with (
                patch.object(capture, "gui", return_value=reported),
                self.assertRaises(capture.CaptureError),
            ):
                capture.read_state()


if __name__ == "__main__":
    unittest.main()
