from __future__ import annotations

import contextlib
import io
import json
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

    def test_error_reader_covers_only_error_code_keys(self) -> None:
        pattern = guard.interpolation_pattern("error.\\(rawValue).message")
        assert pattern is not None
        self.assertTrue(pattern.fullmatch("error.E1001.message"))
        self.assertFalse(pattern.fullmatch("error.E1001"))
        self.assertFalse(pattern.fullmatch("error.noControllerInput.message"))

    def test_interpolated_literal_reads_keys_only_in_key_position(self) -> None:
        source = (
            'let a = Localization().string("error.\\(rawValue).message")\n'
            'var titleKey: String { "area.\\(rawValue).title" }\n'
            'let item = Entry(id: "controllers.\\(controller.id)")\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Source.swift"
            path.write_text(source, encoding="utf-8")
            with mock.patch.object(guard, "reader_files", return_value=[path]):
                _, patterns = guard.key_readers()
        self.assertEqual(
            set(patterns),
            {"error.\\(rawValue).message", "area.\\(rawValue).title"},
        )

    def test_key_call_literals_are_checked_against_the_catalog(self) -> None:
        self.assertEqual(
            guard.key_arguments(
                'let a = StatusItemEntry(title: .key("menuBar.typo"))\n'
            ),
            [(1, '"menuBar.typo"')],
        )

    def test_kept_entry_must_be_unread_and_in_the_catalog(self) -> None:
        guard.KEPT_WITHOUT_READER["gone.key"] = "test"
        guard.KEPT_WITHOUT_READER["read.key"] = "test"
        try:
            problems = guard.stale_kept(["gone.key"], {"read.key", "gone.key"})
        finally:
            del guard.KEPT_WITHOUT_READER["gone.key"]
            del guard.KEPT_WITHOUT_READER["read.key"]
        self.assertEqual(problems, ["kept key 'read.key' has a reader"])


class KeyLiteralTests(unittest.TestCase):
    def test_key_shaped_literal_must_name_a_catalog_key(self) -> None:
        keys = {"ui.area.title", "ui.area.sub.leaf"}
        source = (
            'let a = "ui.area.title"\nlet b = "ui.area.titel"\nlet c = "ui.area.sub."\n'
        )
        self.assertEqual(
            guard.key_literal_problems(source, keys), [(2, "ui.area.titel")]
        )

    def test_literals_outside_the_namespaces_and_named_exceptions_pass(self) -> None:
        source = (
            'let a = "idVendor"\nlet b = "notify.sounds"\nlet c = "ui.\\(x).title"\n'
        )
        self.assertEqual(guard.key_literal_problems(source, set()), [])

    def test_every_named_exception_has_a_reason(self) -> None:
        for key, reason in guard.NOT_A_KEY.items():
            self.assertTrue(reason, key)


class PrefixHelperTests(unittest.TestCase):
    SOURCE = (
        "private func field(_ key: String, _ value: Binding<String>) -> some View {\n"
        "  Text(label(key))\n"
        "}\n"
        "private func label(_ key: String) -> String {\n"
        '  OJDLocalized.string("ui.profiles.gyro." + key)\n'
        "}\n"
        'let rows = [label("deadzone"), field("sensitivty", $x), label(other)]\n'
    )

    def test_literal_arguments_of_the_helper_and_its_forwarders_are_checked(
        self,
    ) -> None:
        keys = {"ui.profiles.gyro.deadzone", "ui.profiles.gyro.sensitivity"}
        self.assertEqual(
            guard.helper_key_problems(self.SOURCE, keys),
            [(7, "ui.profiles.gyro.sensitivty")],
        )

    def test_known_arguments_pass(self) -> None:
        keys = {"ui.profiles.gyro.deadzone", "ui.profiles.gyro.sensitivty"}
        self.assertEqual(guard.helper_key_problems(self.SOURCE, keys), [])

    def test_the_repository_helpers_are_found(self) -> None:
        path = (
            guard.ROOT
            / "Sources/OpenJoystickDriverPresentation/Profiles/AnalogSheets"
            / "ProfileStickFields.swift"
        )
        source = path.read_text(encoding="utf-8")
        self.assertTrue(guard.PREFIX_HELPER.search(source))
        keys = guard.catalog_keys()
        self.assertEqual(guard.helper_key_problems(source, keys), [])
        self.assertGreater(len(guard.helper_key_problems(source, set())), 10)


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
                '<plist version="1.0">\n<dict>\n\t<!-- Count. -->\n\t<key>a.b</key>\n\t<dict>\n'
                "\t\t<key>NSStringLocalizedFormatKey</key>\n\t\t<string>x</string>\n\t</dict>\n"
                "\t<key>c.d</key>\n\t<dict>\n\t\t<key>inner</key>\n\t\t<string>y</string>\n"
                "\t</dict>\n</dict>\n</plist>\n",
                encoding="utf-8",
            )
            self.assertEqual(guard.stringsdict_uncommented_keys(root), {"c.d"})

    def test_unmatched_top_level_key_fails_loudly(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            directory = root / guard.CATALOG_DIRECTORY
            directory.mkdir(parents=True)
            (directory / "Localizable.stringsdict").write_text(
                '<plist version="1.0">\n<dict>\n    <key>a.b</key>\n    <dict/>\n</dict>\n</plist>\n',
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                guard.stringsdict_uncommented_keys(root)


class RuleTests(unittest.TestCase):
    def catalog(self, strings: str, c_strings: str = "") -> Path:
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        resources = root / guard.RESOURCES_DIRECTORY
        for name, text in (("en-US", strings), ("C", c_strings)):
            (resources / f"{name}.lproj").mkdir(parents=True)
            (resources / f"{name}.lproj" / "Localizable.strings").write_text(text)
            (resources / f"{name}.lproj" / "Localizable.stringsdict").write_bytes(
                plistlib.dumps({})
            )
        return root

    def test_each_rule_reports_its_violation_with_the_key(self) -> None:
        root = self.catalog(
            '"bad key" = "Open System Settings %@ %@ %d";\n'
            '/* Label. */\n"ui.fine.title" = "Fine";\n'
        )
        found = guard.rule_problems(root, not_a_count={})
        for rule in ("namespace", "osWord", "specifier", "comment", "pluralCount"):
            self.assertEqual({p.key for p in found[rule]}, {"bad key"}, rule)

    def test_a_conforming_catalog_has_no_violation(self) -> None:
        root = self.catalog('/* Label. */\n"ui.fine.title" = "Fine";\n')
        self.assertEqual(
            {
                rule: p
                for rule, p in guard.rule_problems(root, not_a_count={}).items()
                if p
            },
            {},
        )


class StackedCommentTests(unittest.TestCase):
    def strings_keys(self, text: str) -> list[str]:
        return guard.stacked_comment_keys(
            text, guard.STRINGS_COMMENT, guard.STRINGS_KEY_LINE
        )

    def dict_keys(self, text: str) -> list[str]:
        return guard.stacked_comment_keys(
            text, guard.STRINGSDICT_COMMENT, guard.STRINGSDICT_KEY
        )

    def test_two_comments_above_a_strings_key_fail(self) -> None:
        self.assertEqual(
            self.strings_keys('/* One. */\n/* Two. */\n"a.b" = "A";\n'), ["a.b"]
        )

    def test_a_blank_line_between_the_comments_still_stacks(self) -> None:
        self.assertEqual(
            self.strings_keys('/* One. */\n\n/* Two. */\n"a.b" = "A";\n'), ["a.b"]
        )

    def test_three_comments_report_the_key_once(self) -> None:
        self.assertEqual(
            self.strings_keys('/* 1 */\n/* 2 */\n/* 3 */\n"a.b" = "A";\n'), ["a.b"]
        )

    def test_one_comment_per_key_passes(self) -> None:
        self.assertEqual(
            self.strings_keys('/* One. */\n"a.b" = "A";\n/* Two. */\n"c.d" = "C";\n'),
            [],
        )

    def test_a_comment_inside_a_value_is_not_a_comment(self) -> None:
        self.assertEqual(
            self.strings_keys('/* One. */\n"a.b" = "x /* y */ z";\n"c.d" = "C";\n'), []
        )

    def test_two_comments_above_a_stringsdict_key_fail(self) -> None:
        text = "<dict>\n\t<!-- One. -->\n\t<!-- Two. -->\n\t<key>a.b</key>\n</dict>\n"
        self.assertEqual(self.dict_keys(text), ["a.b"])
        text = "<dict>\n\t<!-- One. -->\n\t<key>a.b</key>\n</dict>\n"
        self.assertEqual(self.dict_keys(text), [])

    def test_the_rule_names_the_bundle_and_the_key(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name) / "de-DE.lproj"
            directory.mkdir()
            (directory / "Localizable.strings").write_text(
                '/* One. */\n/* Two. */\n"a.b" = "A";\n'
            )
            (directory / "Localizable.stringsdict").write_text(
                "<dict>\n\t<!-- One. -->\n\t<!-- Two. -->\n\t<key>c.d</key>\n</dict>\n"
            )
            self.assertEqual(
                [p.message for p in guard.stacked_comment_problems(directory)],
                [
                    "de-DE.lproj/Localizable.strings: 'a.b' has more than one comment above it",
                    "de-DE.lproj/Localizable.stringsdict: 'c.d' has more than one comment above it",
                ],
            )

    def test_the_repository_stacks_no_comment(self) -> None:
        self.assertEqual(
            [
                p.message
                for locale in guard.locale_directories()
                for p in guard.stacked_comment_problems(locale)
            ],
            [],
        )


class StaleNotACountTests(unittest.TestCase):
    entries = [guard.StringsEntry("ui.a.b", "status %d", "Label.")]

    def test_a_key_outside_the_catalog_fails(self) -> None:
        self.assertIn(
            "not in the en-US strings",
            guard.not_a_count_problem("ui.gone.key", self.entries, set()) or "",
        )

    def test_a_value_without_an_integer_specifier_fails(self) -> None:
        entries = [guard.StringsEntry("ui.a.b", "status %@", "Label.")]
        self.assertIn(
            "without an integer specifier",
            guard.not_a_count_problem("ui.a.b", entries, set()) or "",
        )

    def test_a_key_with_a_plural_entry_fails(self) -> None:
        self.assertIn(
            "has a stringsdict entry",
            guard.not_a_count_problem("ui.a.b", self.entries, {"ui.a.b"}) or "",
        )

    def test_a_current_entry_passes(self) -> None:
        self.assertIsNone(guard.not_a_count_problem("ui.a.b", self.entries, set()))

    def test_rule_problems_reports_a_stale_entry_under_the_plural_rule(self) -> None:
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        for name in ("en-US", "C"):
            directory = root / guard.RESOURCES_DIRECTORY / f"{name}.lproj"
            directory.mkdir(parents=True)
            (directory / "Localizable.strings").write_text(
                '/* Label. */\n"ui.fine.title" = "Fine";\n'
            )
            (directory / "Localizable.stringsdict").write_bytes(plistlib.dumps({}))
        found = guard.rule_problems(root, not_a_count={"ui.gone.key": "an exit status"})
        self.assertEqual([p.key for p in found["pluralCount"]], ["ui.gone.key"])


class GateTests(unittest.TestCase):
    def test_each_gated_rule_names_the_task_that_lifts_it(self) -> None:
        self.assertEqual(
            guard.GATED_RULES,
            {"specifier": "22.3", "comment": "22.3", "pluralCount": "22.3"},
        )

    def found(self, rule: str) -> dict[str, list[guard.RuleProblem]]:
        found = {name: [] for name in guard.GATED_RULES}
        found[rule] = [guard.RuleProblem("old.key", "old.key: violation")]
        return found

    def test_gated_rule_holds_back_a_listed_key_only(self) -> None:
        failing, held, stale = guard.rule_report(
            self.found("comment"), {"comment": {"old.key"}}
        )
        self.assertEqual((failing, stale), ([], []))
        self.assertIn("comment: 1 violation(s) held back until task 22.3", held[0])
        failing, _, _ = guard.rule_report(self.found("comment"), {})
        self.assertEqual(failing, ["old.key: violation"])

    def test_key_gated_for_another_rule_fails(self) -> None:
        failing, held, stale = guard.rule_report(
            self.found("specifier"), {"comment": {"old.key"}}
        )
        self.assertEqual(failing, ["old.key: violation"])
        self.assertEqual(held, [])
        self.assertIn("violates no comment rule", stale[0])

    def test_lifted_rule_fails_a_listed_key(self) -> None:
        with mock.patch.dict(guard.GATED_RULES, clear=True):
            failing, held, _ = guard.rule_report(
                self.found("comment"), {"comment": {"old.key"}}
            )
        self.assertEqual((failing, held), (["old.key: violation"], []))

    def test_listed_key_without_a_gated_violation_is_stale(self) -> None:
        _, _, stale = guard.rule_report(
            self.found("comment"), {"comment": {"old.key", "gone.key"}}
        )
        self.assertIn("gone.key", stale[0])

    def test_main_fails_when_a_gate_is_off_and_a_violation_exists(self) -> None:
        violation = {
            "comment": [guard.RuleProblem("old.key", "old.key: no translator comment")]
        }
        for gate in (True, False):
            with (
                mock.patch.object(
                    guard,
                    "rule_problems",
                    return_value={name: [] for name in guard.GATED_RULES} | violation,
                ),
                mock.patch.object(
                    guard, "gated_keys", return_value={"comment": {"old.key"}}
                ),
                mock.patch.dict(
                    guard.GATED_RULES,
                    {"comment": "22.3"} if gate else {},
                    clear=True,
                ),
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                self.assertEqual(guard.main([]), 0 if gate else 1, gate)

    def test_the_repository_passes_with_the_gates_it_has(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(guard.main([]), 0)


class WriteGatedKeysTests(unittest.TestCase):
    def update(
        self,
        violating: dict[str, set[str]],
        gated: dict[str, set[str]],
    ) -> tuple[dict[str, list[str]], list[str]]:
        found = {
            rule: [
                guard.RuleProblem(key, f"{key}: {rule}")
                for key in violating.get(rule, ())
            ]
            for rule in guard.GATED_RULES
        }
        with (
            mock.patch.object(guard, "rule_problems", return_value=found),
            mock.patch.object(
                guard,
                "gated_keys",
                return_value={
                    rule: gated.get(rule, set()) for rule in guard.GATED_RULES
                },
            ),
        ):
            return guard.update_gated_keys(Path("."))

    def test_a_new_violation_is_refused_with_its_key_and_rule(self) -> None:
        _, refused = self.update(
            {"comment": {"old.key", "new.key"}}, {"comment": {"old.key"}}
        )
        self.assertEqual(len(refused), 1)
        self.assertIn("'new.key'", refused[0])
        self.assertIn("comment", refused[0])

    def test_refused_update_writes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            path = root / guard.GATED_KEYS_PATH
            path.parent.mkdir(parents=True)
            path.write_text("unchanged")
            with mock.patch.object(
                guard, "update_gated_keys", return_value=({}, ["refused"])
            ):
                self.assertEqual(guard.write_gated_keys(root), ["refused"])
            self.assertEqual(path.read_text(), "unchanged")

    def test_stale_and_missing_entries_are_removed(self) -> None:
        data, refused = self.update(
            {"comment": {"kept.key"}},
            {
                "comment": {"kept.key", "fixed.key", "gone.key"},
                "specifier": {"fixed.key"},
            },
        )
        self.assertEqual(refused, [])
        self.assertEqual(data["comment"], ["kept.key"])
        self.assertEqual(data["specifier"], [])


class WriteGatedKeysCommandTests(unittest.TestCase):
    def repository(self, keys: list[str], gated: list[str]) -> Path:
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        directory = root / guard.CATALOG_DIRECTORY
        directory.mkdir(parents=True)
        (directory / "Localizable.strings").write_text(
            "".join(f'"{key}" = "Text";\n' for key in keys)
        )
        (directory / "Localizable.stringsdict").write_bytes(plistlib.dumps({}))
        c_directory = root / guard.RESOURCES_DIRECTORY / "C.lproj"
        c_directory.mkdir(parents=True)
        (c_directory / "Localizable.strings").write_text("")
        (c_directory / "Localizable.stringsdict").write_bytes(plistlib.dumps({}))
        path = root / guard.GATED_KEYS_PATH
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"comment": gated}))
        return root

    def run_main(self, root: Path, *arguments: str) -> tuple[int, str]:
        errors = io.StringIO()
        with (
            mock.patch.object(guard, "ROOT", root),
            mock.patch.dict(guard.NOT_A_COUNT, clear=True),
            contextlib.redirect_stderr(errors),
        ):
            code = guard.main(["--write-gated-keys", *arguments])
        return code, errors.getvalue()

    def gated(self, root: Path) -> list[str]:
        data = json.loads((root / guard.GATED_KEYS_PATH).read_text())
        return data["comment"]

    def test_the_write_keeps_the_listed_violations(self) -> None:
        root = self.repository(["ui.a.one", "ui.a.two"], ["ui.a.one", "ui.a.two"])
        code, _ = self.run_main(root)
        self.assertEqual(code, 0)
        self.assertEqual(self.gated(root), ["ui.a.one", "ui.a.two"])

    def test_an_unlisted_violation_is_refused(self) -> None:
        root = self.repository(["ui.a.one", "ui.a.two"], ["ui.a.one"])
        code, errors = self.run_main(root)
        self.assertEqual(code, 1)
        self.assertIn("'ui.a.two'", errors)
        self.assertEqual(self.gated(root), ["ui.a.one"])

    def test_another_argument_is_a_usage_error(self) -> None:
        root = self.repository(["ui.a.one"], ["ui.a.one"])
        code, errors = self.run_main(root, "--gate", "ui.a.one", "comment")
        self.assertEqual(code, 2)
        self.assertIn("usage:", errors)


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
