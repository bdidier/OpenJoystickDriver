"""Runs `OJDRepositoryTool`, the development executable that holds the Swift checks.

The patch merge and the record rules live in Swift only. This module builds the tool with
SwiftPM and runs one of its subcommands; each problem the tool prints is one JSON line
`{file, code, message}`.
"""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
from dataclasses import dataclass

ROOT = pathlib.Path(__file__).resolve().parents[2]
PRODUCT = "OJDRepositoryTool"


class RepositoryToolError(OSError):
    """The tool could not be built or run, or it refused the call."""


@dataclass(frozen=True)
class Problem:
    file: str
    code: str
    message: str

    def __str__(self) -> str:
        return f"{self.file}: {self.code}: {self.message}"


def _swift(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    swift = shutil.which("swift")
    if swift is None:
        raise RepositoryToolError(
            f"swift is not installed; {PRODUCT} needs the Swift toolchain"
        )
    return subprocess.run(
        [swift, "build", *arguments],
        cwd=ROOT,
        capture_output=True,
        check=False,
        text=True,
    )


def executable() -> pathlib.Path:
    """Builds the tool and returns its path."""
    built = _swift(["--product", PRODUCT])
    if built.returncode:
        raise RepositoryToolError(
            f"swift build --product {PRODUCT} failed:\n{built.stderr.strip()}"
        )
    located = _swift(["--show-bin-path"])
    if located.returncode:
        raise RepositoryToolError(
            f"swift build --show-bin-path failed:\n{located.stderr.strip()}"
        )
    path = pathlib.Path(located.stdout.strip()) / PRODUCT
    if not path.is_file():
        raise RepositoryToolError(f"{PRODUCT} was not built at {path}")
    return path


def run(arguments: list[str]) -> list[Problem]:
    """Runs one subcommand and returns the problems it prints.

    Exit status 1 is a result: the problems are the answer. Any other failure is an error.
    """
    result = subprocess.run(
        [str(executable()), *arguments],
        cwd=ROOT,
        capture_output=True,
        check=False,
        text=True,
    )
    if result.returncode not in {0, 1}:
        raise RepositoryToolError(
            f"{PRODUCT} {' '.join(arguments)} failed with status {result.returncode}:\n"
            f"{result.stderr.strip()}"
        )
    problems: list[Problem] = []
    for line in result.stdout.splitlines():
        try:
            fields = json.loads(line)
            problems.append(Problem(fields["file"], fields["code"], fields["message"]))
        except (json.JSONDecodeError, KeyError, TypeError) as error:
            raise RepositoryToolError(
                f"{PRODUCT} printed a line that is not a problem: {line}"
            ) from error
    if (result.returncode == 1) != bool(problems):
        raise RepositoryToolError(
            f"{PRODUCT} exited {result.returncode} with {len(problems)} problem(s)"
        )
    return problems
