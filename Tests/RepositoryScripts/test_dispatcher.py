from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from Scripts.Command import dispatcher


class TargetInvoked(Exception):
    pass


class DispatcherTests(unittest.TestCase):
    root = Path(__file__).resolve().parents[2]
    command = root / "Scripts/ojd"

    def run_ojd(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self.command), *arguments],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_help_route_succeeds(self) -> None:
        self.assertEqual(self.run_ojd("--help").returncode, 0)

    def test_help_flags_and_help_word_succeed_on_stdout(self) -> None:
        for argument in ("-h", "--help", "help"):
            with self.subTest(argument=argument):
                result = self.run_ojd(argument)
                self.assertEqual(result.returncode, 0)
                self.assertTrue(result.stdout.strip())
                self.assertEqual(result.stderr, "")

    def test_version_reports_the_app_version(self) -> None:
        result = self.run_ojd("--version")
        self.assertEqual(result.returncode, 0)
        self.assertIn(dispatcher.project_version(), result.stdout)

    def test_errors_use_lowercase_prefix_on_stderr(self) -> None:
        for arguments in (("unknown",), ("build", "nuke"), ("--bogus",)):
            with self.subTest(arguments=arguments):
                result = self.run_ojd(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn("error:", result.stderr)
                self.assertNotIn("ERROR:", result.stderr)

    def test_build_help_route_succeeds(self) -> None:
        self.assertEqual(self.run_ojd("build", "help").returncode, 0)

    def test_build_routes_forward_arguments(self) -> None:
        routes = (
            (
                ("build", "dev"),
                "Build/build.sh",
                ["build", "dev"],
                None,
            ),
            (
                ("build", "release"),
                "Build/build.sh",
                ["build", "release"],
                {"OJD_ENV": "release"},
            ),
            (
                ("build", "dext"),
                "Build/build.sh",
                ["build", "dext"],
                None,
            ),
            (
                ("build", "install", "dev"),
                "Build/install.sh",
                ["install", "dev"],
                None,
            ),
            (
                ("build", "install", "release"),
                "Build/install.sh",
                ["install", "release"],
                {"OJD_ENV": "release"},
            ),
            (
                ("build", "install-fast", "dev"),
                "Build/install.sh",
                ["install-fast", "dev"],
                None,
            ),
        )
        for arguments, target, forwarded_arguments, environment in routes:
            with self.subTest(arguments=arguments):
                with (
                    patch.object(
                        dispatcher,
                        "exec_target",
                        side_effect=TargetInvoked,
                    ) as execute,
                    self.assertRaises(TargetInvoked),
                ):
                    dispatcher.dispatch(list(arguments))
                execute.assert_called_once_with(
                    target,
                    forwarded_arguments,
                    env=environment,
                )

    def test_snapshots_routes_forward_to_the_comparison_script(self) -> None:
        for argument in ("check", "write"):
            with self.subTest(argument=argument):
                with (
                    patch.object(
                        dispatcher,
                        "exec_target",
                        side_effect=TargetInvoked,
                    ) as execute,
                    self.assertRaises(TargetInvoked),
                ):
                    dispatcher.dispatch(["snapshots", argument])
                execute.assert_called_once_with(
                    "Quality/equivalence_snapshots.py",
                    [argument],
                    python=True,
                )

    def test_unknown_route_fails_with_usage_status(self) -> None:
        self.assertEqual(self.run_ojd("unknown").returncode, 2)

    def test_removed_routes_fail_with_usage_status(self) -> None:
        for arguments in (
            ("build", "nuke"),
            ("check", "scripts"),
            ("check", "swift-structure"),
            ("check", "capabilities"),
            ("check", "fast"),
            ("check", "all"),
            ("lint",),
            ("format",),
            ("test", "swift"),
        ):
            with self.subTest(arguments=arguments):
                self.assertEqual(self.run_ojd(*arguments).returncode, 2)

    def test_check_tools_runs_xmake_with_the_environment(self) -> None:
        completed = subprocess.CompletedProcess(args=[], returncode=0)
        with patch.object(
            dispatcher.subprocess, "run", return_value=completed
        ) as run_command:
            self.assertEqual(dispatcher.dispatch(["check", "tools"]), 0)
        command = run_command.call_args_list[0].args[0]
        self.assertEqual(command[:2], ["/bin/bash", "-c"])
        self.assertIn('source "$1"', command[2])
        self.assertIn("exec xmake build", command[2])
        self.assertEqual(
            command[4:],
            [
                str(dispatcher.ENVIRONMENT),
                str(dispatcher.PROJECT_DIR / "Tools/SDLGamepadProbe"),
            ],
        )

    def test_check_tools_runs_the_bridge_package_tests(self) -> None:
        completed = subprocess.CompletedProcess(args=[], returncode=0)
        with patch.object(
            dispatcher.subprocess, "run", return_value=completed
        ) as run_command:
            dispatcher.dispatch(["check", "tools"])
        self.assertEqual(run_command.call_count, 2)
        call = run_command.call_args_list[1]
        self.assertEqual(
            call.kwargs["cwd"], dispatcher.PROJECT_DIR / "Tools/WebRTCBridge"
        )
        command = call.args[0]
        self.assertIn('exec "$SWIFT_BIN"', command[2])
        self.assertEqual(command[5:], ["test"])

    def test_check_tools_fails_when_the_bridge_tests_fail(self) -> None:
        results = [
            subprocess.CompletedProcess(args=[], returncode=0),
            subprocess.CompletedProcess(args=[], returncode=1),
        ]
        with patch.object(dispatcher.subprocess, "run", side_effect=results):
            self.assertEqual(dispatcher.dispatch(["check", "tools"]), 1)

    def test_hooks_install_runs_bun_install(self) -> None:
        completed = subprocess.CompletedProcess([], 0)
        with patch(
            "Scripts.Command.execution.subprocess.run", return_value=completed
        ) as run:
            self.assertEqual(dispatcher.dispatch(["hooks", "install"]), 0)
        self.assertEqual(run.call_args.args[0], ["bun", "install"])

    def test_hooks_validate_checks_hooks_path_and_hook_files(self) -> None:
        all_files = ("commit-msg", "pre-commit", "pre-push")
        main = "<main>/.husky/_"
        for configured, generated, files, expected in (
            (main, True, all_files, 0),
            (".husky/_", True, all_files, 1),
            ("", True, all_files, 1),
            ("legacy/hooks", True, all_files, 1),
            (main, False, all_files, 1),
            (main, True, ("pre-commit", "pre-push"), 1),
        ):
            with (
                self.subTest(configured=configured, generated=generated, files=files),
                tempfile.TemporaryDirectory() as directory,
            ):
                root = Path(directory)
                (root / ".husky").mkdir()
                if generated:
                    (root / ".husky" / "_").mkdir()
                for name in files:
                    (root / ".husky" / name).write_text("")
                value = configured.replace("<main>", str(root))
                completed = subprocess.CompletedProcess([], 0, value + "\n", "")
                with (
                    patch("Scripts.Command.execution.PROJECT_DIR", root),
                    patch(
                        "Scripts.Command.execution.main_checkout_dir",
                        return_value=root,
                    ),
                    patch(
                        "Scripts.Command.execution.subprocess.run",
                        return_value=completed,
                    ),
                ):
                    self.assertEqual(
                        dispatcher.dispatch(["hooks", "validate"]), expected
                    )
