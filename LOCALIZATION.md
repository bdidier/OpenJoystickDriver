# Localization

Use this procedure to update one shipped locale without changing keys or runtime identifiers.

One Foundation catalog in `OpenJoystickDriverKit`. macOS preferred-language order picks the locale. No in-app switcher.

## Files

- `Sources/OpenJoystickDriverKit/Resources/en-US.lproj/Localizable.strings` and `.stringsdict`: the source catalog.
- Shipped locales: `Sources/OpenJoystickDriverKit/Resources/<locale>.lproj/Localizable.strings` and `.stringsdict`.
- `crowdin.yml`: the Crowdin project configuration.

`Package.swift` default is `en-US`. `Scripts/Build/bundles.sh` copies Kit locales into the app. Kit `Localization` falls back to `en-US`. App: `OJDLocalized`. CLI: `CLILocalized`.

English text lives only in the `en-US` catalog. Call sites pass a key and nothing else: there is no `fallback:` or `defaultValue:` argument, so a key missing from `en-US` renders as the raw key. Add the key to `en-US` and to every other locale before using it.

`python3 Scripts/Quality/check_localization_keys.py` fails when a literal key passed to `OJDLocalized`, `CLILocalized`, `Localization`, or `LocalizedStringResource` is missing from `en-US`. It checks a literal prefix of a dynamic key such as `"error.\(rawValue)"` against the catalog. It cannot check keys held in variables or passed through helper parameters; it lists them as `key not scanned`.

## Key rules

`python3 Scripts/Quality/check_localization_keys.py` enforces these rules on the catalog.

- Namespace: a key starts with `term.`, `action.`, `status.`, `ui.<area>.`, `ui.menu.`, `ui.extra.`, `ui.settings.<pane>.`, `a11y.`, `cli.<group>.<command>.`, `error.<code>.`, `notify.` or `platform.<os>.`.
  Segments are lowerCamelCase; only an error code such as `E1001` is capitalized.
- Operating system words: `DriverKit`, `macOS`, `Mac`, `Apple`, `System Settings`, `Login Items`, `Finder`, `IOKit`, `systemextensionsctl`, `launchd`, `Xcode`, `Input Monitoring`, `Privacy & Security`, `Dock`, `Terminal`, `TCC`, `codesign` and `Accessibility` as a permission or pane name appear in an English value only under `platform.<os>.`. A neutral key carries the neutral wording.
- Specifiers: a value with more than one format specifier numbers each one (`%1$@ of %2$@`), so a translation can reorder them. A single specifier needs no number.
- Plurals: a key that takes a count (`%#@name@` or an integer specifier such as `%d`, `%lld`, `%1$lld` in `en-US`) has a `.stringsdict` entry in every bundle, with at least the plural forms CLDR gives that language, listed in `Resources/Localization/PluralCategories.json`, which the checker and `LocalizationTests` both read (`ar`: zero, one, two, few, many, other; `ru`: one, few, many, other; `es`, `fr`, `it`, `pt`: one, many, other; `en`, `de`, `hi`, `nl`, `tr`: one, other; `id`, `ja`, `ko`, `th`, `vi`, `zh`: other). An integer specifier that is not a count is listed in `NOT_A_COUNT` in the checker with the reason.
- Comments: every `en-US` key has a translator comment, a `/* ... */` directly above the entry in `.strings` and a `<!-- ... -->` above the key in `.stringsdict`. The comment says where the text appears and what each specifier is.

The checker fails on every rule above except where `GATED_RULES` in the checker holds a rule back. A held-back rule (`namespace`, `osWord`, `specifier`, `comment`, `pluralCount`) does not fail on the keys listed under it in `Scripts/Quality/localization-gated-keys.json` (`{"rule": ["key", ...]}`) and fails on every other key, so a key cannot add a violation of a rule it is not listed under. A key listed under a rule it no longer violates fails the check. The check prints how many violations each held-back rule holds.

- `python3 Scripts/Quality/check_localization_keys.py --write-gated-keys` only removes entries: keys that no longer violate their rule and keys that no longer exist. A violation that is not listed makes it fail with the key and the rule, and it writes nothing.
- `--write-gated-keys --gate KEY RULE` (repeatable) adds exactly the named pairs. It accepts only `namespace`, and only for a key that violates it and belongs to a family that a key-building reader in `Sources` reads (such as `error.E####` through `error.\(rawValue)`) whose other keys are all gated for `namespace`. That reader builds the key from a code or a prefix, so the key cannot take the namespace shape before the re-key. Any other addition is refused with the reason. `comment`, `osWord`, `specifier` and `pluralCount` violations are fixed on the key itself and are never added.

## Crowdin

`crowdin.yml` sets `en-US.lproj/*.strings` and `en-US.lproj/*.stringsdict` as the sources, and `%osx_locale%.lproj/%original_file_name%` as the translation path. Its `languages_mapping` names the 20 translated bundles; `C.lproj` copies the English source and is not translated. Credentials come from `CROWDIN_PROJECT_ID` and `CROWDIN_PERSONAL_TOKEN`; the file holds none.

1. Change `en-US` (key, value and comment) and run the checker.
2. Crowdin reads the new sources and the translators fill each locale.
3. Download the translations into the `<locale>.lproj` folders and review them against [Meaning](#meaning) and [Punctuation](#punctuation) before the commit.

22 `.lproj` bundles: `C`, `en-US`, `ar-SA`, `de-DE`, `es-ES`, `es-MX`, `fr-CA`, `fr-FR`, `hi-IN`, `id-ID`, `it-IT`, `ja-JP`, `ko-KR`, `nl-NL`, `pt-BR`, `ru-RU`, `th-TH`, `tr-TR`, `vi-VN`, `zh-CN`, `zh-HK`, `zh-TW`.
Three plural keys in `en-US` (`status.controllerConnected`, `profiles.assignments`, `debug.outputDevices`).
Every non-English locale began as a machine translation and needs review against the rules in [Meaning](#meaning).
English source catalogs are `en-US` and `C`.
Ship only languages that macOS itself offers.

## Punctuation

- English source: ASCII `...` and `'`.
- Translations: native `…`, quotes (`„…“`, `«…»`, `「…」`), `→` for arrows.
- `pt-BR` and `es-MX` quote with `“…”`; `es-ES` keeps `«…»`.
- French: NBSP before `:` and inside `« »`. `fr-FR` puts a narrow NBSP (U+202F) before `; ? !`; `fr-CA` puts no space there.
- No ASCII `"` inside a `.strings` value.
- Numeric ranges stay `0...255`.

## Meaning

A value is wrong when it reads well but says something else.
Read every value back against `en-US` before you ship it.

- Translate the sense the app uses, not the first dictionary sense.
  "Disabled" means turned off, not a person.
  "Pitch", "Yaw", and "Roll" are rotation axes.
  "Motion" is the motion sensor, "Trigger" is the shoulder trigger, and "Escape" is the key name.
- For a short label, read the call site in `Sources/` before you pick a word.
- A label stays a label.
  A one- or two-word English label never becomes a sentence, a reply, or a line with a leading dialogue dash such as `- Yes.`.
- Keys with different English get different values.
  Two keys share a value only when their `en-US` values match.
- Keep the part of speech: a noun label stays a noun, and an action button stays a verb.
- Use one term per concept in a file: controller, profile, mapping, service, extension, pairing.
  Keep a diagnose "check" distinct from the controller device.
- For a standard macOS term (menu items, keys, common buttons), use the term Apple's macOS glossary uses in that language when it has the same sense.
- Leave English only for product names, CLI tokens and option values, identifiers, and a loanword that macOS itself uses in that language.
- Do not ship unreviewed machine translation. Whoever adds or changes a value, person or agent, reviews it against these rules before the commit; an agent reads each value back against `en-US` and its call site, and fixes what fails. Native speakers review on top when they can.

## Translate

1. Copy the `en-US` key shape and comments into the target `.lproj` pair.
2. Translate values. Keep keys, placeholders (`%@`, `%1$@`, `%d`, `%#@count@`), and runtime identifiers (names, VID/PID, paths).
3. One key per label. Follow Apple's capitalization and verb form for the language. Native ellipsis only when the command needs more input before it completes (Apple's menu rule); an item that only opens a window or a submenu has none.
4. RTL: check mixed-direction names and paths.

Capability messages describe the controller or active protocol, not a permanent profile error. Compact symbol actions still require localized text because that text is used for older-system fallbacks, tooltips, and accessibility labels.

Put the language first in macOS to try it.

```bash
export DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer
swift test --filter OpenJoystickDriverKitTests.LocalizationTests
```
