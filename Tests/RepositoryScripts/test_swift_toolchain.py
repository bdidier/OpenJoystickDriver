from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from Scripts.Command.execution import swift_command


class SwiftToolchainTests(unittest.TestCase):
    def test_swift_command_runs_the_swift_found_on_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            swift = Path(directory) / "swift"
            swift.write_text(
                '#!/bin/sh\n[ "$1" = --version ] && echo "Apple Swift version 6.4.1" && exit 0\n'
                'echo "ran:$0:$*"\n',
                encoding="utf-8",
            )
            swift.chmod(0o755)
            env = {**os.environ, "PATH": f"{directory}:{os.environ['PATH']}"}
            result = subprocess.run(
                swift_command(["build", "--show-bin-path"]),
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"ran:{swift}:build --show-bin-path")


if __name__ == "__main__":
    unittest.main()
