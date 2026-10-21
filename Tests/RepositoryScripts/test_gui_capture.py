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


UNLOCKED = "locked=false console=true"


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
            return "Activity" if command[0] == "current-sidebar" else ""

        with (
            tempfile.TemporaryDirectory() as root,
            patch.object(capture, "PROJECT_DIR", Path(root)),
            patch.object(capture, "process_id", return_value=1),
            patch.object(capture, "require_unlocked_console_session"),
            patch.object(capture, "require_accessibility"),
            patch.object(capture, "require_english_ui"),
            patch.object(capture, "run"),
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
                ("select-sidebar", "Activity"),
                ("close-window", "settings"),
                ("close-window", "main"),
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
                ("select-sidebar", "Activity"),
                ("open-settings", "General"),
            ],
        )
        self.assertNotIn(("close-window", "main"), calls)

    def test_failed_capture_keeps_its_error_and_still_restores(self) -> None:
        failures: dict[str, Exception] = {
            "open-settings": capture.CaptureError("menu failed"),
            "close-window": capture.CaptureError("no window"),
        }
        code, calls, error = self.run_capture(
            (False, None), failures, ["--settings-pane", "General"]
        )
        self.assertIsNone(code)
        self.assertEqual(str(error), "menu failed")
        self.assertEqual(calls[-3][0], "select-sidebar")
        self.assertEqual(calls[-1], ("close-window", "main"))

    def test_failed_restore_step_does_not_skip_later_steps(self) -> None:
        failures: dict[str, Exception] = {
            "select-sidebar": capture.CaptureError("row missing")
        }
        code, calls, error = self.run_capture(
            (False, None), failures, ["--settings-pane", "General"]
        )
        self.assertEqual((code, error), (2, None))
        self.assertEqual(calls[-1], ("close-window", "main"))

    def completed(self, code: int, out: str) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess([], code, out, "")

    def probe_message(self, code: str) -> str | None:
        with patch.object(capture, "ax", return_value=code) as probe:
            try:
                capture.require_accessibility(7)
            except capture.CaptureError as error:
                message = str(error)
            else:
                message = None
        probe.assert_called_once_with("probe", 7)
        return message

    def test_accessibility_probe_granted_lets_capture_continue(self) -> None:
        self.assertIsNone(self.probe_message("0"))

    def test_accessibility_probe_untrusted_names_the_permission(self) -> None:
        message = self.probe_message("-25211")
        assert message is not None
        self.assertIn("Accessibility is not granted to the host app", message)
        self.assertIn("-25211", message)
        self.assertIn("Privacy & Security > Accessibility", message)

    def test_run_names_the_host_app_for_an_untrusted_ax_error(self) -> None:
        failure = subprocess.CompletedProcess(
            [], 1, "", "execution error: AXError -25211"
        )
        with (
            patch.object(subprocess, "run", return_value=failure),
            self.assertRaises(capture.CaptureError) as raised,
        ):
            capture.run(["osascript", "-l", "JavaScript"])
        self.assertEqual(str(raised.exception), capture.not_trusted_message("-25211"))

    def test_run_does_not_blame_permission_for_the_word_assistive(self) -> None:
        failure = subprocess.CompletedProcess([], 1, "", "assistive access failed")
        with (
            patch.object(subprocess, "run", return_value=failure),
            self.assertRaises(capture.CaptureError) as raised,
        ):
            capture.run(["osascript", "-l", "JavaScript"])
        self.assertNotIn("not granted", str(raised.exception))

    def test_accessibility_probe_other_failure_does_not_ask_for_permission(
        self,
    ) -> None:
        message = self.probe_message("-25202")
        assert message is not None
        self.assertIn("Accessibility call to OpenJoystickDriver failed", message)
        self.assertIn("-25202", message)
        self.assertIn("although the host app is trusted", message)
        self.assertNotIn("Privacy & Security", message)

    def wait_for_app(
        self, codes: list[str], timeout: float = 5.0
    ) -> tuple[str | None, int, list[float]]:
        now = [0.0]
        sleeps: list[float] = []

        def sleep(seconds: float) -> None:
            sleeps.append(seconds)
            now[0] += seconds

        with patch.object(capture, "ax", side_effect=codes) as probe:
            try:
                capture.require_accessibility(7, timeout, lambda: now[0], sleep)
            except capture.CaptureError as error:
                return str(error), probe.call_count, sleeps
        return None, probe.call_count, sleeps

    def test_app_ready_immediately_does_not_wait(self) -> None:
        self.assertEqual(self.wait_for_app(["0"]), (None, 1, []))

    def test_app_ready_after_cannot_complete_probes_waits_then_continues(self) -> None:
        message, probes, sleeps = self.wait_for_app(["-25204", "-25204", "0"])
        self.assertEqual((message, probes), (None, 3))
        self.assertEqual(sleeps, [capture.APP_READY_POLL_SECONDS] * 2)

    def test_app_not_ready_by_the_deadline_names_app_wait_timeout_and_error(
        self,
    ) -> None:
        message, probes, _ = self.wait_for_app(["-25204"] * 100, timeout=1.0)
        assert message is not None
        self.assertIn("OpenJoystickDriver did not answer Accessibility", message)
        self.assertIn("within 1 s", message)
        self.assertIn("last AXError -25204", message)
        self.assertIn("--ready-timeout", message)
        self.assertEqual(probes, 5)

    def test_other_probe_errors_are_not_waited_on(self) -> None:
        message, probes, sleeps = self.wait_for_app(["-25202"])
        assert message is not None
        self.assertEqual((probes, sleeps), (1, []))

    def test_ready_timeout_option_is_positive(self) -> None:
        self.assertEqual(
            capture.parse_args(["--all", "--ready-timeout", "3"]).ready_timeout, 3.0
        )
        self.assertEqual(
            capture.parse_args(["--all"]).ready_timeout,
            capture.APP_READY_TIMEOUT_SECONDS,
        )
        for value in ("0", "-1", "nan", "inf"):
            with self.subTest(value=value), self.assertRaises(SystemExit):
                capture.parse_args(["--all", "--ready-timeout", value])

    def test_untrusted_after_cannot_complete_stops_the_wait(self) -> None:
        message, probes, sleeps = self.wait_for_app(["-25204", "-25211"])
        assert message is not None
        self.assertIn("Accessibility is not granted to the host app", message)
        self.assertEqual((probes, len(sleeps)), (2, 1))

    def test_last_sleep_does_not_pass_the_deadline(self) -> None:
        _, _, sleeps = self.wait_for_app(["-25204"] * 100, timeout=0.6)
        self.assertEqual(len(sleeps), 3)
        self.assertAlmostEqual(sum(sleeps), 0.6)

    def test_capture_passes_the_ready_timeout_to_the_wait(self) -> None:
        with (
            patch.object(capture, "process_id", return_value=7),
            patch.object(capture, "session_state", return_value=UNLOCKED),
            patch.object(
                capture, "require_accessibility", side_effect=TargetInvoked
            ) as wait,
            self.assertRaises(TargetInvoked),
        ):
            capture.capture(
                capture.parse_args(["--area", "Controllers", "--ready-timeout", "4"])
            )
        wait.assert_called_once_with(7, 4.0)

    def test_capture_probes_after_finding_the_app_and_before_any_gui_call(
        self,
    ) -> None:
        order: list[str] = []
        with (
            patch.object(
                capture, "process_id", side_effect=lambda: order.append("pid") or 7
            ),
            patch.object(
                capture,
                "ax",
                side_effect=lambda *call: order.append("probe") or "-25211",
            ),
            patch.object(capture, "session_state", return_value=UNLOCKED),
            patch.object(capture, "gui") as gui,
            self.assertRaises(capture.CaptureError),
        ):
            capture.capture(capture.parse_args(["--area", "Controllers"]))
        self.assertEqual(order, ["pid", "probe"])
        gui.assert_not_called()

    def session_message(self, reported: str) -> str | None:
        with patch.object(capture, "session_state", return_value=reported):
            try:
                capture.require_unlocked_console_session()
            except capture.CaptureError as error:
                return str(error)
        return None

    def test_unlocked_console_session_lets_capture_continue(self) -> None:
        self.assertIsNone(self.session_message(UNLOCKED))

    def test_locked_screen_is_named(self) -> None:
        message = self.session_message("locked=true console=true")
        assert message is not None
        self.assertIn("the screen is locked: unlock this Mac's session", message)

    def test_session_off_the_console_is_named(self) -> None:
        message = self.session_message("locked=false console=false")
        assert message is not None
        self.assertIn("not on the console", message)
        self.assertNotIn("screen is locked", message)

    def test_unreadable_session_state_fails(self) -> None:
        message = self.session_message("garbage")
        assert message is not None
        self.assertIn("session state reported 'garbage'", message)

    def test_locked_screen_stops_before_the_accessibility_probe(self) -> None:
        with (
            patch.object(capture, "process_id", return_value=7),
            patch.object(
                capture, "session_state", return_value="locked=true console=true"
            ),
            patch.object(capture, "ax") as probe,
            self.assertRaises(capture.CaptureError),
        ):
            capture.capture(capture.parse_args(["--area", "Controllers"]))
        probe.assert_not_called()

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
