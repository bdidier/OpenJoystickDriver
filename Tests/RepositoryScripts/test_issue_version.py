"""Behavior tests for the issue version check."""

from __future__ import annotations

import unittest

from Scripts.Documentation.issues.version_check import (
    reported_version,
    version_problem,
)

FULL = "0.6.0-alpha.1+build.1.8.74.sha.08bc747d93f6.dirty (1.8.74)"


def form_body(version: str) -> str:
    return (
        "### OpenJoystickDriver version\n\n"
        f"{version}\n\n"
        "### Where the build came from\n\n"
        "GitHub release\n"
    )


class IssueVersionTests(unittest.TestCase):
    def test_accepts_the_about_window_line(self) -> None:
        self.assertIsNone(version_problem(FULL))

    def test_accepts_build_metadata_without_the_bundle_suffix(self) -> None:
        self.assertIsNone(version_problem("0.6.0+build.1.9.0.sha.08bc747d93f6"))

    def test_rejects_versions_without_build_metadata(self) -> None:
        for value in ("0.6.0-alpha.1", "alpha", "beta", "latest", ""):
            with self.subTest(value=value):
                self.assertIsNotNone(version_problem(value))

    def test_rejects_a_short_commit(self) -> None:
        self.assertIsNotNone(version_problem("0.6.0+build.1.8.74.sha.08bc747"))

    def test_rejects_a_suffix_that_names_another_build(self) -> None:
        self.assertIsNotNone(
            version_problem("0.6.0+build.1.8.74.sha.08bc747d93f6 (1.8.75)")
        )

    def test_reads_the_version_field_of_a_form_body(self) -> None:
        self.assertEqual(reported_version(form_body(f"`{FULL}`")), FULL)

    def test_reads_no_version_from_an_empty_field_or_a_blank_issue(self) -> None:
        self.assertIsNone(reported_version(form_body("_No response_")))
        self.assertIsNone(reported_version("It does not work."))


if __name__ == "__main__":
    unittest.main()
