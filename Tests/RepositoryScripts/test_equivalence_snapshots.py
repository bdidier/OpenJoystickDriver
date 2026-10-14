from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from Scripts.Quality import equivalence_snapshots as snapshots


class EquivalenceSnapshotTests(unittest.TestCase):
    def test_sections_are_keyed_by_title(self) -> None:
        text = "## A\none\ntwo\n\n## B\nthree\n"
        self.assertEqual(
            snapshots.parse_sections(text), {"A": "one\ntwo", "B": "three"}
        )

    def test_diff_names_changed_added_and_removed_records(self) -> None:
        expected = "## A\nx\n\n## B\ny\n\n## C\nz\n"
        actual = "## A\nx\n\n## B\nY\n\n## D\nw\n"
        self.assertEqual(
            snapshots.diff_sections(expected, actual),
            [
                "  changed B",
                "    - y",
                "    + Y",
                "  removed C",
                "  added   D",
            ],
        )

    def test_equal_text_has_no_difference(self) -> None:
        self.assertEqual(snapshots.diff_sections("## A\nx\n", "## A\nx\n"), [])

    def test_compare_reports_only_files_that_differ(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            recorded = Path(directory, "recorded")
            current = Path(directory, "current")
            recorded.mkdir()
            current.mkdir()
            (recorded / "same.txt").write_text("## A\nx\n")
            (current / "same.txt").write_text("## A\nx\n")
            (recorded / "moved.txt").write_text("## A\nx\n")
            (current / "moved.txt").write_text("## A\nz\n")
            result = snapshots.compare(recorded, current)
        self.assertEqual(list(result), ["moved.txt"])

    def test_unknown_argument_fails_with_usage_status(self) -> None:
        self.assertEqual(snapshots.main(["bogus"]), 2)

    def test_pure_reorder_shows_lines(self) -> None:
        self.assertEqual(
            snapshots.diff_sections("## A\nx\ny\n", "## A\ny\nx\n"),
            ["  changed A", "    + y", "    - y"],
        )

    def test_duplicate_line_shows_lines(self) -> None:
        self.assertEqual(
            snapshots.diff_sections("## A\nx\n", "## A\nx\nx\n"),
            ["  changed A", "    + x"],
        )

    def test_header_before_first_section_is_ignored(self) -> None:
        self.assertEqual(
            snapshots.diff_sections("# note\n\n## A\nx\n", "# other\n\n## A\nx\n"),
            [],
        )


class EquivalenceSnapshotCommandTests(unittest.TestCase):
    """Runs check() and write() with a fake test run in place of `swift test`."""

    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.snapshots = self.root / "Tests" / "EquivalenceSnapshots"
        self.snapshots.mkdir(parents=True)
        for target, value in (("ROOT", self.root), ("SNAPSHOTS", self.snapshots)):
            patcher = mock.patch.object(snapshots, target, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def fake_run(self, produced: dict[str, str], status: int = 0):
        def run(extra: dict[str, str]) -> int:
            if "OJD_SNAPSHOT_ACTUAL_DIR" in extra:
                target = Path(extra["OJD_SNAPSHOT_ACTUAL_DIR"])
                for name, text in produced.items():
                    (target / name).write_text(text)
            if extra.get("OJD_SNAPSHOT_WRITE") == "1":
                for name, text in produced.items():
                    (self.snapshots / name).write_text(text)
            return status

        return mock.patch.object(snapshots, "run_tests", side_effect=run)

    def run_check(self, produced: dict[str, str], status: int = 0) -> tuple[int, str]:
        output = io.StringIO()
        with self.fake_run(produced, status), contextlib.redirect_stdout(output):
            code = snapshots.check()
        return code, output.getvalue()

    def test_check_passes_when_the_tree_matches(self) -> None:
        (self.snapshots / "a.txt").write_text("## A\nx\n")
        code, output = self.run_check({"a.txt": "## A\nx\n"})
        self.assertEqual(code, 0)
        self.assertIn("No differences", output)

    def test_check_reports_a_changed_record(self) -> None:
        (self.snapshots / "a.txt").write_text("## A\nx\n\n## B\ny\n")
        code, output = self.run_check({"a.txt": "## A\nx\n\n## B\nz\n"})
        self.assertEqual(code, 1)
        self.assertIn("  changed B", output)
        self.assertIn("1 difference(s)", output)

    def test_check_reports_a_record_no_longer_produced(self) -> None:
        (self.snapshots / "a.txt").write_text("## A\nx\n\n## B\ny\n")
        code, output = self.run_check({"a.txt": "## A\nx\n"})
        self.assertEqual(code, 1)
        self.assertIn("  removed B", output)

    def test_check_reports_a_missing_snapshot_file(self) -> None:
        code, output = self.run_check({"a.txt": "## A\nx\n"})
        self.assertEqual(code, 1)
        self.assertIn("snapshot file is missing", output)
        self.assertIn("  added   A", output)

    def test_check_reports_a_snapshot_file_no_longer_produced(self) -> None:
        (self.snapshots / "gone.txt").write_text("## A\nx\n")
        code, output = self.run_check({})
        self.assertEqual(code, 1)
        self.assertIn("no longer produced by the tree", output)

    def test_check_returns_the_test_status_when_tests_fail(self) -> None:
        (self.snapshots / "a.txt").write_text("## A\nx\n")
        code, _ = self.run_check({"a.txt": "## A\nx\n"}, status=3)
        self.assertEqual(code, 3)

    def test_write_rewrites_the_snapshots_then_check_passes(self) -> None:
        (self.snapshots / "a.txt").write_text("## A\nold\n")
        output = io.StringIO()
        with (
            self.fake_run({"a.txt": "## A\nnew\n"}),
            contextlib.redirect_stdout(output),
        ):
            code = snapshots.write()
        self.assertEqual(code, 0)
        self.assertEqual((self.snapshots / "a.txt").read_text(), "## A\nnew\n")
        self.assertIn("Rewrote", output.getvalue())
        self.assertEqual(self.run_check({"a.txt": "## A\nnew\n"})[0], 0)

    def test_write_returns_the_test_status_when_tests_fail(self) -> None:
        output = io.StringIO()
        with self.fake_run({}, status=2), contextlib.redirect_stdout(output):
            self.assertEqual(snapshots.write(), 2)
        self.assertNotIn("Rewrote", output.getvalue())


if __name__ == "__main__":
    unittest.main()
