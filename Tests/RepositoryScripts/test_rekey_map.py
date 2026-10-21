from __future__ import annotations

import json
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
                bool(guard.OS_WORDS.search(self.current[old])),
                new.startswith("platform.macos."),
                old,
            )

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
        }
        for old, new in samples.items():
            self.assertIn(self.mapping[old], (new, f"platform.macos.{new}"), old)


if __name__ == "__main__":
    unittest.main()
