# Documentation Instructions

`wiki/` is user documentation and the GitHub wiki source (`./Scripts/ojd docs build-wiki OUTDIR`; publish with `just wiki`, `--dry-run` to preview). Developer and hardware-evidence pages go in `docs/`. This file is not published.

- Write for users: GitHub Docs style, ASD-STE100 prose. No hard wraps.
- Flat folder, `Title-Case-With-Hyphens.md`. List every page in `Home.md` and `_Sidebar.md` in the same groups.
- One sentence-case H1, a one-sentence intro, `## Further reading` when related pages exist. Pages over ~100 lines get a generated `## Contents`.
- Link as `Page.md#anchor` or a relative path outside `wiki/`. No footnotes, images, source paths or line numbers.
- Procedures: numbered, one action per step, UI labels in bold.
- Ground claims in source, tests or hardware evidence; otherwise write "not verified". Hardware observations go in `docs/testing/`.
- No schemas, evidence dumps or generated matrices, except the generated blocks of `Error-Codes.md` (`./Scripts/ojd errors regenerate --write`) and `Controller-Records.md` (`./Scripts/ojd vocabulary regenerate --write`); edit those only via their sources.
