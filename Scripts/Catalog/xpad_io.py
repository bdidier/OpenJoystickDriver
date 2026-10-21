"""The gh command and JSON text shared by the catalog generator."""

from __future__ import annotations

import json
import pathlib
import subprocess
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[2]


def run_gh(args: list[str], failure: type[Exception]) -> str:
    command = ["gh", *args]
    result = subprocess.run(
        command, cwd=ROOT, capture_output=True, check=False, text=True
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise failure(f"{' '.join(command)} failed: {detail}")
    return result.stdout


def json_text(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"
