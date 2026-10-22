"""`Scripts/Quality/repository_tool.py` fails loudly and builds the tool once."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from Scripts.Quality import repository_tool


def completed(status: int, stdout: str = "", stderr: str = "") -> object:
    return subprocess.CompletedProcess([], status, stdout=stdout, stderr=stderr)


class RunTests(unittest.TestCase):
    def problems(self, status: int, stdout: str = "") -> list[dict[str, str]]:
        with (
            patch.object(repository_tool, "binary", return_value=Path("tool")),
            patch.object(
                repository_tool.subprocess,
                "run",
                return_value=completed(status, stdout),
            ),
        ):
            return repository_tool.problems(["validate", "records", "x"])

    def test_a_problem_line_is_returned(self) -> None:
        line = '{"file": "a.json", "code": "E5007", "message": "m"}\n'
        self.assertEqual(
            self.problems(1, line),
            [{"file": "a.json", "code": "E5007", "message": "m"}],
        )

    def test_a_clean_run_has_no_problem(self) -> None:
        self.assertEqual(self.problems(0), [])

    def test_a_refused_call_raises(self) -> None:
        with self.assertRaises(repository_tool.ToolError):
            self.problems(64)

    def test_status_and_output_must_agree(self) -> None:
        line = '{"file": "a", "code": "c", "message": "m"}\n'
        with self.assertRaises(repository_tool.ToolError):
            self.problems(1)
        with self.assertRaises(repository_tool.ToolError):
            self.problems(0, line)

    def test_a_line_that_is_not_a_problem_raises(self) -> None:
        for line in ("not json\n", '{"file": "a"}\n', "[1]\n"):
            with self.assertRaises(repository_tool.ToolError, msg=line):
                self.problems(1, line)


class BuildTests(unittest.TestCase):
    def test_the_tool_is_built_once_for_many_runs(self) -> None:
        repository_tool.binary.cache_clear()
        self.addCleanup(repository_tool.binary.cache_clear)
        with (
            patch.object(repository_tool, "build", return_value=Path("tool")) as build,
            patch.object(repository_tool.subprocess, "run", return_value=completed(0)),
        ):
            repository_tool.check(["validate", "records", "x"])
            repository_tool.check(["validate", "records", "y"])
        build.assert_called_once_with(repository_tool.PRODUCT)

    def test_a_failed_build_raises(self) -> None:
        failure = subprocess.CalledProcessError(1, "swift", stderr="boom")
        with (
            patch.object(repository_tool.subprocess, "run", side_effect=failure),
            self.assertRaisesRegex(repository_tool.ToolError, "boom"),
        ):
            repository_tool.build("OJDRepositoryTool")

    def test_a_missing_executable_raises(self) -> None:
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(
                repository_tool.subprocess,
                "run",
                return_value=completed(0, stdout=f"{directory}\n"),
            ),
            self.assertRaises(repository_tool.ToolError),
        ):
            repository_tool.build("OJDRepositoryTool")


if __name__ == "__main__":
    unittest.main()
