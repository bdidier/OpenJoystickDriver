from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

from Scripts.Catalog import generate_crosswalk as crosswalk

ROOT = Path(__file__).resolve().parents[2]
COPIED = (crosswalk.CROSSWALK, crosswalk.WIKI_PAGE)


class CrosswalkTableTests(unittest.TestCase):
    def copy_repository(self) -> Path:
        directory = Path(tempfile.mkdtemp(prefix="ojd-crosswalk-"))
        self.addCleanup(shutil.rmtree, directory)
        for path in COPIED:
            (directory / path).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / path, directory / path)
        return directory

    def edit_crosswalk(
        self, root: Path, control: str, column: str, value: object
    ) -> None:
        path = root / crosswalk.CROSSWALK
        document = json.loads(path.read_text(encoding="utf-8"))
        document["controls"][control][column] = value
        path.write_text(json.dumps(document), encoding="utf-8")

    def test_the_wiki_table_matches_the_json(self) -> None:
        self.assertEqual(crosswalk.regenerate(ROOT, write=False), [])

    def test_the_table_has_a_row_per_control_and_a_source_per_column(self) -> None:
        page = (ROOT / crosswalk.WIKI_PAGE).read_text(encoding="utf-8")
        document = json.loads((ROOT / crosswalk.CROSSWALK).read_text(encoding="utf-8"))
        for control in document["controls"]:
            self.assertIn(f"| `{control}` |", page)
        for column in document["sources"].values():
            self.assertIn(column["url"], page)

    def test_a_changed_json_cell_makes_the_wiki_stale(self) -> None:
        root = self.copy_repository()
        self.edit_crosswalk(root, "South", "sdl", "NOT_SOUTH")
        self.assertEqual(crosswalk.regenerate(root, write=False), [crosswalk.WIKI_PAGE])
        self.assertEqual(crosswalk.regenerate(root, write=True), [crosswalk.WIKI_PAGE])
        self.assertEqual(crosswalk.regenerate(root, write=False), [])
        self.assertIn(
            "`NOT_SOUTH`", (root / crosswalk.WIKI_PAGE).read_text(encoding="utf-8")
        )

    def test_a_changed_wiki_cell_is_found(self) -> None:
        root = self.copy_repository()
        page = root / crosswalk.WIKI_PAGE
        text = page.read_text(encoding="utf-8")
        page.write_text(text.replace("`BTN_SOUTH`", "`BTN_A`", 1), encoding="utf-8")
        self.assertEqual(crosswalk.regenerate(root, write=False), [crosswalk.WIKI_PAGE])

    def test_a_page_without_the_markers_is_refused(self) -> None:
        root = self.copy_repository()
        page = root / crosswalk.WIKI_PAGE
        page.write_text(
            page.read_text(encoding="utf-8").replace(crosswalk.BEGIN, ""),
            encoding="utf-8",
        )
        with self.assertRaises(crosswalk.CrosswalkError):
            crosswalk.regenerate(root, write=False)

    def test_a_column_without_a_source_is_refused(self) -> None:
        root = self.copy_repository()
        path = root / crosswalk.CROSSWALK
        document = json.loads(path.read_text(encoding="utf-8"))
        del document["sources"]["apple"]
        path.write_text(json.dumps(document), encoding="utf-8")
        with self.assertRaises(crosswalk.CrosswalkError):
            crosswalk.regenerate(root, write=False)


if __name__ == "__main__":
    unittest.main()
