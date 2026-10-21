from __future__ import annotations

import json
import re
import unittest

from Scripts.Quality import check_localization_keys as guard
from Scripts.Quality import rekey_map as rekey


class RekeyMapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mapping: dict[str, str] = json.loads(
            (rekey.ROOT / rekey.MAP_PATH).read_text(encoding="utf-8")
        )["keys"]
        cls.current = rekey.english_values(rekey.ROOT)
        cls.by_pattern = rekey.pattern_read_keys(cls.current)
        cls.tree = rekey.command_tree()

    def test_map_covers_every_current_key_and_nothing_else(self) -> None:
        self.assertEqual(
            sorted(set(self.current) - set(self.mapping)), [], "run rekey_map --write"
        )
        self.assertEqual(sorted(set(self.mapping) - set(self.current)), [])

    def test_map_matches_the_rules(self) -> None:
        self.assertEqual(
            rekey.render(), (rekey.ROOT / rekey.MAP_PATH).read_text(encoding="utf-8")
        )

    def test_new_keys_are_unique(self) -> None:
        self.assertEqual(len(set(self.mapping.values())), len(self.mapping))

    def test_new_keys_match_the_namespace_rules(self) -> None:
        bad = [new for new in self.mapping.values() if guard.key_shape_problem(new)]
        self.assertEqual(bad, [])

    def test_operating_system_values_move_under_platform(self) -> None:
        for old, new in self.mapping.items():
            self.assertEqual(
                bool(guard.OS_WORDS.search(self.current[old]))
                and old not in self.by_pattern,
                new.startswith("platform.macos."),
                old,
            )

    def test_keys_read_by_pattern_are_never_platform_prefixed(self) -> None:
        for old in self.by_pattern:
            self.assertFalse(self.mapping[old].startswith("platform."), old)

    def test_pattern_read_operating_system_values_are_listed_for_rewording(
        self,
    ) -> None:
        listed = json.loads(rekey.render())["neutralTextRequired"]
        self.assertEqual(
            listed,
            sorted(
                old
                for old in self.by_pattern
                if guard.OS_WORDS.search(self.current[old])
            ),
        )
        self.assertIn("error.E2008", listed)

    def test_every_key_under_a_read_by_pattern_prefix_keeps_one_prefix_and_suffix(
        self,
    ) -> None:
        _, patterns = guard.key_readers(rekey.ROOT)
        checked = 0
        for name, pattern in patterns.items():
            skeletons: set[str] = set()
            for old in self.by_pattern:
                match = pattern.fullmatch(old)
                if match is None:
                    continue
                if name.endswith(" + <text>"):
                    variables = [old[len(name.removesuffix("<text>").rstrip("+ ")) :]]
                else:
                    variables = self.interpolated(name, old)
                skeletons.add(self.skeleton(self.mapping[old], variables))
                checked += 1
            self.assertLessEqual(len(skeletons), 1, (name, skeletons))
        self.assertGreater(checked, 100)

    def test_error_code_keys_read_by_swift_get_the_message_suffix(self) -> None:
        for old, new in self.mapping.items():
            if old.startswith("error.E"):
                self.assertEqual(new, f"{old}.message", old)

    def test_cli_commands_come_from_the_command_tree(self) -> None:
        self.assertIn("list", self.tree["controller"])
        self.assertIn("export_mapping", self.tree["virtual"])
        for old, new in self.mapping.items():
            parts = old.split(".")
            if parts[0] != "cli" or parts[1] in rekey.SHARED_CLI_GROUPS:
                continue
            command = new.removeprefix("platform.macos.").split(".")[2]
            group = parts[1]
            if command == "group":
                self.assertFalse(
                    len(parts) > 3 and parts[2] in self.tree.get(group, ()), old
                )
            else:
                self.assertIn(parts[2], self.tree[group], old)

    def test_names_that_are_not_commands_stay_in_the_group(self) -> None:
        for old in (
            "cli.permission.name.input_read",
            "cli.permission.pane.input_read",
            "cli.permission.purpose.usb_transport",
            "cli.status.label.controllers",
            "cli.controller.selector.ambiguous",
            "cli.diagnose.usb.ok",
            "cli.diagnose.timings.frame",
            "cli.binding.clear.done",
        ):
            new = self.mapping[old].removeprefix("platform.macos.")
            if old.startswith("cli.binding"):
                self.assertEqual(new.split(".")[2], "clear", old)
            else:
                self.assertEqual(new.split(".")[2], "group", old)

    @staticmethod
    def interpolated(literal: str, old: str) -> list[str]:
        """Return the text of each interpolation in `old`, read with the pieces of `literal`."""
        pieces = re.split(r"\\\([^)]*\)", literal)
        regex = "(.+?)".join(re.escape(piece) for piece in pieces)
        match = re.fullmatch(regex, old)
        assert match is not None
        return list(match.groups())

    @staticmethod
    def skeleton(new: str, variables: list[str]) -> str:
        """Return `new` with each variable replaced by a marker, in order."""
        position = 0
        out = ""
        for variable in variables:
            index = new.find(variable, position)
            assert index >= 0, (new, variable)
            out += new[position:index] + "\0"
            position = index + len(variable)
        return out + new[position:]

    def test_rules_on_sample_keys(self) -> None:
        samples = {
            "common.ok": "action.ok",
            "common.status": "term.status",
            "status.ready": "status.ready",
            "keyboard.escape": "term.key.escape",
            "controller.xboxOne": "term.controllerModel.xboxOne",
            "settings.startAtLogin": "ui.settings.general.startAtLogin",
            "settingsPane.advanced.title": "ui.settings.advanced.title",
            "cli.controller.list.abstract": "cli.controller.list.abstract",
            "cli.controller.abstract": "cli.controller.group.abstract",
            "cli.error.service_timeout": "cli.shared.error.serviceTimeout",
            "cli.diagnose.output_progress": "cli.diagnose.group.outputProgress",
            "mainMenu.file.saveSupportReport": "ui.menu.file.saveSupportReport",
            "mainMenu.file": "ui.menu.file.title",
            "menuBar.suspend": "ui.extra.suspend",
            "a11y.settingsPane.general": "a11y.settingsPane.general",
            "error.E2008": "error.E2008.message",
        }
        for old, new in samples.items():
            self.assertIn(self.mapping[old], (new, f"platform.macos.{new}"), old)


if __name__ == "__main__":
    unittest.main()
