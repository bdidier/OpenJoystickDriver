from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
