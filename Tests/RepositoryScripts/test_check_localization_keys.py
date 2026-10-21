from __future__ import annotations

import contextlib
import io
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from Scripts.Quality import check_localization_keys as guard

KEYS = {"common.ok", "error.one", "error.two"}


class KeyArgumentTests(unittest.TestCase):
    def test_reads_first_argument_of_each_call_form(self) -> None:
        source = (
            'OJDLocalized.string("common.ok")\n'
            'CLILocalized.format("error.one", a, b)\n'
            'LocalizedStringResource("error.two")\n'
            "OJDLocalized.plural(key, count: 2)\n"
        )
        self.assertEqual(
            guard.key_arguments(source),
            [(1, '"common.ok"'), (2, '"error.one"'), (3, '"error.two"'), (4, "key")],
        )

    def test_nested_calls_and_interpolation_do_not_split_the_argument(self) -> None:
        source = 'OJDLocalized.string("error.\\(f(a, b))", x)'
        self.assertEqual(guard.key_arguments(source), [(1, '"error.\\(f(a, b))"')])


class ProblemTests(unittest.TestCase):
    def test_known_literal_passes(self) -> None:
        self.assertIsNone(guard.problems('"common.ok"', KEYS))

    def test_unknown_literal_fails(self) -> None:
        self.assertIn("bogus.key", guard.problems('"bogus.key"', KEYS) or "")

    def test_ternary_checks_both_branches(self) -> None:
        self.assertIsNone(guard.problems('flag ? "error.one" : "error.two"', KEYS))
        self.assertIn(
            "bogus", guard.problems('flag ? "error.one" : "bogus"', KEYS) or ""
        )

    def test_prefix_needs_a_matching_key(self) -> None:
        self.assertIsNone(guard.problems('"error.\\(code)"', KEYS))
        self.assertIsNone(guard.problems('"error." + name', KEYS))
        self.assertIn("nope.", guard.problems('"nope.\\(code)"', KEYS) or "")

    def test_fully_dynamic_key_is_not_judged(self) -> None:
        self.assertIsNone(guard.problems("key", KEYS))


class ReaderTests(unittest.TestCase):
    def test_string_literals_skip_comments_and_keep_interpolations(self) -> None:
        source = (
            '// "commented.key"\nlet a = "area.\\(raw).title"\n'
            '/* "block.key" */\nlet b = """\n"multi.line"\n"""\nlet c = "plain.key"\n'
        )
        self.assertEqual(
            guard.string_literals(source), ["area.\\(raw).title", "plain.key"]
        )

    def test_interpolated_key_matches_with_each_interpolation_as_any_text(self) -> None:
        pattern = guard.interpolation_pattern("area.\\(raw).title")
        assert pattern is not None
        self.assertTrue(pattern.fullmatch("area.status.title"))
        self.assertFalse(pattern.fullmatch("area.status.subtitle"))

    def test_interpolation_without_a_dotted_prefix_reads_nothing(self) -> None:
        self.assertIsNone(guard.interpolation_pattern("a\\(index)"))
        self.assertIsNone(guard.interpolation_pattern("\\(prefix).title"))

    def test_kept_entry_must_be_unread_and_in_the_catalog(self) -> None:
        guard.KEPT_WITHOUT_READER["gone.key"] = "test"
        guard.KEPT_WITHOUT_READER["read.key"] = "test"
        try:
            problems = guard.stale_kept(["gone.key"], {"read.key", "gone.key"})
        finally:
            del guard.KEPT_WITHOUT_READER["gone.key"]
            del guard.KEPT_WITHOUT_READER["read.key"]
        self.assertEqual(problems, ["kept key 'read.key' has a reader"])


class NamespaceTests(unittest.TestCase):
    def test_every_namespace_has_an_accepted_key(self) -> None:
        for key in (
            "term.controller",
            "action.save",
            "status.ready",
            "a11y.access.details",
            "notify.profileSwitched",
            "ui.access.title",
            "ui.menu.main.app.settings",
            "ui.settings.general.title",
            "cli.controller.list.abstract",
            "error.E1001.message",
            "platform.macos.ui.setup.openSystemSettings",
            "platform.macos.error.E2008.message",
        ):
            self.assertIsNone(guard.key_shape_problem(key), key)

    def test_key_outside_the_namespaces_fails(self) -> None:
        self.assertIn(
            "outside the namespaces", guard.key_shape_problem("common.ok") or ""
        )

    def test_bare_namespace_fails(self) -> None:
        self.assertIsNotNone(guard.key_shape_problem("term"))
        self.assertIsNotNone(guard.key_shape_problem("ui.access"))

    def test_segment_must_be_lower_camel_case(self) -> None:
        for key in (
            "action.Save",
            "ui.access.snake_case",
            "status.1st",
            "ui.access.Title",
        ):
            self.assertIsNotNone(guard.key_shape_problem(key), key)

    def test_error_code_is_the_only_capitalized_segment(self) -> None:
        self.assertIsNotNone(guard.key_shape_problem("error.profileChanged"))
        self.assertIsNotNone(guard.key_shape_problem("error.E10.message"))
        self.assertIsNotNone(guard.key_shape_problem("error.E1001"))

    def test_cli_key_needs_group_command_and_leaf(self) -> None:
        self.assertIsNotNone(guard.key_shape_problem("cli.controller.abstract"))

    def test_settings_key_needs_a_pane_and_a_leaf(self) -> None:
        self.assertIsNotNone(guard.key_shape_problem("ui.settings.general"))

    def test_platform_key_needs_a_known_operating_system(self) -> None:
        self.assertIsNotNone(guard.key_shape_problem("platform.beos.setup.title"))
        self.assertIsNotNone(guard.key_shape_problem("platform.macos"))


class OperatingSystemWordTests(unittest.TestCase):
    def test_operating_system_word_outside_platform_fails(self) -> None:
        for value in (
            "Needs DriverKit",
            "Open System Settings",
            "Left to macOS",
            "Show in Finder",
            "Apple signed it",
            "on this Mac",
        ):
            self.assertIn(
                "outside platform.", guard.os_word_problem("ui.a.b", value) or ""
            )

    def test_platform_key_may_name_the_operating_system(self) -> None:
        self.assertIsNone(
            guard.os_word_problem("platform.macos.ui.a.b", "Needs DriverKit")
        )

    def test_neutral_value_passes(self) -> None:
        self.assertIsNone(guard.os_word_problem("ui.a.b", "Remaps the Machine"))


class SpecifierTests(unittest.TestCase):
    def test_two_unnumbered_specifiers_fail(self) -> None:
        self.assertIsNotNone(guard.specifier_problem("ui.a.b", "%@ of %@"))
        self.assertIsNotNone(guard.specifier_problem("ui.a.b", "%@ of %1$@"))
        self.assertIsNotNone(guard.specifier_problem("ui.a.b", "%lld of %.2f"))

    def test_numbered_specifiers_pass(self) -> None:
        self.assertIsNone(guard.specifier_problem("ui.a.b", "%1$@ of %2$@"))

    def test_one_specifier_needs_no_position(self) -> None:
        self.assertIsNone(guard.specifier_problem("ui.a.b", "Open %@"))
        self.assertIsNone(guard.specifier_problem("ui.a.b", "100%% of %@"))


class CommentTests(unittest.TestCase):
    def test_entry_reads_the_comment_directly_above(self) -> None:
        entries = guard.strings_entries(
            '/* Section */\n\n"a.b" = "A";\n/* Button label. */\n"c.d" = "C";\n'
            '"e.f" = "E";\n'
        )
        self.assertEqual(
            [(e.key, e.comment) for e in entries],
            [("a.b", None), ("c.d", "Button label."), ("e.f", None)],
        )

    def test_entry_without_a_comment_fails(self) -> None:
        entry = guard.StringsEntry("a.b", "A", None)
        self.assertIn("no translator comment", guard.comment_problem(entry) or "")
        self.assertIsNone(
            guard.comment_problem(guard.StringsEntry("a.b", "A", "Label."))
        )


class PluralTests(unittest.TestCase):
    def bundle(self, name: str, strings: str, categories: tuple[str, ...]) -> Path:
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        directory = Path(scratch.name) / name
        directory.mkdir()
        (directory / "Localizable.strings").write_text(strings, encoding="utf-8")
        plurals = {}
        if categories:
            plurals["status.count"] = {
                "NSStringLocalizedFormatKey": "%#@count@",
                "count": {category: "%d" for category in categories},
            }
        (directory / "Localizable.stringsdict").write_bytes(plistlib.dumps(plurals))
        return directory

    def test_count_value_without_a_stringsdict_entry_fails(self) -> None:
        directory = self.bundle("en-US.lproj", '"a.b" = "%#@count@";\n', ())
        self.assertIn(
            "has no stringsdict entry", "".join(guard.plural_problems(directory))
        )

    def test_locale_missing_a_category_fails(self) -> None:
        directory = self.bundle("ru-RU.lproj", "", ("one", "other"))
        self.assertIn(
            "lacks the plural forms ['few', 'many']",
            "".join(guard.plural_problems(directory)),
        )

    def test_locale_with_its_categories_passes(self) -> None:
        directory = self.bundle("ja-JP.lproj", "", ("other",))
        self.assertEqual(guard.plural_problems(directory), [])


class AccessibilityAndPermissionWordTests(unittest.TestCase):
    def test_permission_and_pane_names_are_operating_system_words(self) -> None:
        for value in (
            "Input Monitoring",
            "Accessibility",
            "Privacy & Security > Accessibility",
            "Show in Dock",
            "Run ojd in Terminal",
            "not a TCC privacy permission",
            "Could not run codesign",
            "Accessibility permission required",
        ):
            self.assertIn(
                "outside platform.", guard.os_word_problem("ui.a.b", value) or "", value
            )

    def test_the_generic_word_accessibility_passes(self) -> None:
        for value in ("Accessibility details", "Improves accessibility", "Docking"):
            self.assertIsNone(guard.os_word_problem("ui.a.b", value), value)


class CountSpecifierTests(unittest.TestCase):
    def entry(self, value: str, key: str = "ui.a.b") -> guard.StringsEntry:
        return guard.StringsEntry(key, value, "Label.")

    def test_integer_specifiers_without_a_plural_entry_fail(self) -> None:
        for value in ("%d items", "%lld items", "%ld", "%lu", "%li", "%1$lld of %2$d"):
            self.assertIn(
                "needs a stringsdict entry",
                guard.count_specifier_problem(self.entry(value), set()) or "",
                value,
            )

    def test_plural_entry_and_non_integer_specifiers_pass(self) -> None:
        self.assertIsNone(guard.count_specifier_problem(self.entry("%d"), {"ui.a.b"}))
        for value in ("%@ items", "%.1f MiB", "100%% of %@", "%1$@"):
            self.assertIsNone(
                guard.count_specifier_problem(self.entry(value), set()), value
            )

    def test_not_a_count_key_passes_with_its_reason(self) -> None:
        guard.NOT_A_COUNT["ui.a.b"] = "an exit status"
        try:
            self.assertIsNone(
                guard.count_specifier_problem(self.entry("status %d"), set())
            )
        finally:
            del guard.NOT_A_COUNT["ui.a.b"]

    def test_every_not_a_count_entry_has_a_reason(self) -> None:
        for key, reason in guard.NOT_A_COUNT.items():
            self.assertTrue(reason.strip(), key)


class StringsdictCommentTests(unittest.TestCase):
    def test_only_top_level_keys_are_read_and_found_once(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            directory = root / guard.CATALOG_DIRECTORY
            directory.mkdir(parents=True)
            (directory / "Localizable.stringsdict").write_text(
                "<dict>\n\t<!-- Count. -->\n\t<key>a.b</key>\n\t<dict>\n"
                "\t\t<key>NSStringLocalizedFormatKey</key>\n\t</dict>\n"
                "\t<key>c.d</key>\n\t<dict>\n\t\t<key>inner</key>\n\t</dict>\n</dict>\n",
                encoding="utf-8",
            )
            self.assertEqual(guard.stringsdict_uncommented_keys(root), {"c.d"})


class RuleTests(unittest.TestCase):
    def catalog(self, strings: str, c_strings: str = "") -> Path:
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        resources = root / guard.RESOURCES_DIRECTORY
        for name, text in (("en-US", strings), ("C", c_strings)):
            (resources / f"{name}.lproj").mkdir(parents=True)
            (resources / f"{name}.lproj" / "Localizable.strings").write_text(text)
        (resources / "en-US.lproj" / "Localizable.stringsdict").write_bytes(
            plistlib.dumps({})
        )
        return root

    def test_each_rule_reports_its_violation_with_the_key(self) -> None:
        root = self.catalog(
            '"bad key" = "Open System Settings %@ %@ %d";\n'
            '/* Label. */\n"ui.fine.title" = "Fine";\n'
        )
        found = guard.rule_problems(root)
        for rule in ("namespace", "osWord", "specifier", "comment", "pluralCount"):
            self.assertEqual({p.key for p in found[rule]}, {"bad key"}, rule)

    def test_a_conforming_catalog_has_no_violation(self) -> None:
        root = self.catalog('/* Label. */\n"ui.fine.title" = "Fine";\n')
        self.assertEqual(
            {rule: p for rule, p in guard.rule_problems(root).items() if p}, {}
        )


class GateTests(unittest.TestCase):
    def test_each_gated_rule_names_the_task_that_lifts_it(self) -> None:
        self.assertEqual(
            guard.GATED_RULES,
            {
                "namespace": "22.2",
                "osWord": "22.2",
                "specifier": "22.3",
                "comment": "22.3",
                "pluralCount": "22.3",
            },
        )

    def found(self, rule: str) -> dict[str, list[guard.RuleProblem]]:
        found = {name: [] for name in guard.GATED_RULES}
        found[rule] = [guard.RuleProblem("old.key", "old.key: violation")]
        return found

    def test_gated_rule_holds_back_a_listed_key_only(self) -> None:
        failing, held, stale = guard.rule_report(self.found("comment"), {"old.key"})
        self.assertEqual((failing, stale), ([], []))
        self.assertIn("comment: 1 violation(s) held back until task 22.3", held[0])
        failing, _, _ = guard.rule_report(self.found("comment"), set())
        self.assertEqual(failing, ["old.key: violation"])

    def test_lifted_rule_fails_a_listed_key(self) -> None:
        with mock.patch.dict(guard.GATED_RULES, clear=True):
            failing, held, _ = guard.rule_report(self.found("comment"), {"old.key"})
        self.assertEqual((failing, held), (["old.key: violation"], []))

    def test_listed_key_without_a_gated_violation_is_stale(self) -> None:
        _, _, stale = guard.rule_report(self.found("comment"), {"old.key", "gone.key"})
        self.assertIn("gone.key", stale[0])

    def test_main_fails_when_a_gate_is_off_and_a_violation_exists(self) -> None:
        violation = {"osWord": [guard.RuleProblem("old.key", "old.key: names macOS")]}
        for gate in (True, False):
            with (
                mock.patch.object(
                    guard,
                    "rule_problems",
                    return_value={name: [] for name in guard.GATED_RULES} | violation,
                ),
                mock.patch.object(guard, "gated_keys", return_value={"old.key"}),
                mock.patch.dict(
                    guard.GATED_RULES,
                    {"osWord": "22.2"} if gate else {},
                    clear=True,
                ),
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                self.assertEqual(guard.main([]), 0 if gate else 1, gate)

    def test_the_repository_passes_with_the_gates_it_has(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(guard.main([]), 0)


class RepositoryTests(unittest.TestCase):
    def test_en_us_catalog_covers_every_scannable_key(self) -> None:
        missing, _ = guard.check()
        self.assertEqual(missing, [])

    def test_every_catalog_key_has_a_reader_or_a_stated_reason(self) -> None:
        unread, _ = guard.unread_keys()
        self.assertEqual(
            [key for key in unread if key not in guard.KEPT_WITHOUT_READER], []
        )


if __name__ == "__main__":
    unittest.main()
