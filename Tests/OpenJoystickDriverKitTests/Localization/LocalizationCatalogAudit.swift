import Foundation

@testable import OpenJoystickDriverKit

enum LocalizationCatalogAudit {
  static let nonLinguisticSourceIdenticalKeys: Set<String> = [
    "app.name", "controller.dualSense", "controller.dualShock3", "controller.dualShock4",
    "controller.flydigi", "controller.genericHID", "controller.originalXbox",
    "controller.standardHID", "controller.steamController", "controller.switchPro",
    "controller.switchProController", "controller.xbox360", "controller.xbox360Wireless",
    "controller.xbox360WirelessDeveloper", "controller.xboxOne", "controller.xboxOriginal",
    "controllers.usbIdentifier", "developer.hid", "developer.usbID", "inputTest.yTriangle",
    "mapping.buttonNorth", "mapping.dpadDirection", "menu.projectPage", "profiles.sectionDpad",
    "access.transport.web", "access.web",
  ]

  private static let spanishTerms: Set<String> = [
    "developer.packetColumnBytes", "inputTest.color", "keyboard.control", "profiles.controlNumber",
    "profiles.motion.local",
    "profiles.physical.motor", "profiles.stick.horizontal", "profiles.stick.vertical",
    "profiles.trackball.enabled", "profiles.turbo",
    "library.mods", "access.scope.control", "access.socket", "access.transport.socket",
    "access.tokens", "access.token.issued.title", "access.token.named",
    "settingsPane.general.title",
  ]
  private static let frenchTerms: Set<String> = [
    "library.field.source", "library.field.transport", "library.field.version", "capture.gain",
    "cli.controller.show.label.session",
    "cli.status.label.transport_extension", "cli.status.label.service", "common.destination",
    "inputTest.menu", "keyboard.alt", "mapping.guide",
    "mapping.start", "motion.calibration.pause",
    "profiles.activationMode", "profiles.motion.local", "profiles.sectionSticks",
    "profiles.stick.horizontal", "profiles.stick.source", "profiles.stick.vertical",
    "profiles.touch.surface", "profiles.trackball.enabled", "profiles.turbo",
    "settings.notifications", "settings.version", "access.transport.socket", "access.web.port",
    "library.mods",
  ]

  private static let sourceIdenticalTermsByLocale: [String: Set<String>] = [
    "ar-SA": [
      "keyboard.meta", "keyboard.control", "keyboard.escape", "keyboard.alt",
      "keyboard.return", "keyboard.shift", "keyboard.tab",
    ],
    "de-DE": [
      "library.field.version", "mainMenu.controller",
      "access.details", "library.details",
      "access.token.name", "access.web.port", "access.web.enable.port", "access.socket",
      "access.transport.socket", "access.token.issued.title", "access.token.named",
      "access.tokens", "library.mods",
      "capture.linear", "cli.access.status.socket",
      "cli.controller.show.label.name", "common.controller", "common.status", "console.stream",
      "developer.controller", "developer.controllerDetails",
      "developer.route", "inputTest.home", "keyboard.control", "keyboard.escape", "mapping.guide",
      "mapping.start", "profiles.physical.motor", "profiles.sectionSticks",
      "profiles.stick.horizontal", "profiles.stick.source", "profiles.trackball.enabled",
      "profiles.trigger.source", "profiles.turbo", "settings.updates", "settings.version",
      "shortcuts.controller.name", "shortcuts.controller.type", "shortcuts.parameter.controller",
      "shortcuts.profile.name",
    ],
    "es-ES": spanishTerms.union(["mainMenu.window.zoom"]),
    "es-MX": spanishTerms.union(["mainMenu.window.zoom"]),
    "fr-CA": frenchTerms.union(["developer.packetColumnDirection"]).union([
      "mainMenu.app.services", "mainMenu.window.zoom", "settingsPane.notifications.title",
    ]),
    "fr-FR": frenchTerms.union([
      "mainMenu.app.services", "mainMenu.window.zoom", "settingsPane.notifications.title",
    ]),
    "hi-IN": ["keyboard.escape", "keyboard.return"],
    "id-ID": [
      "library.layer.driver", "access.token.issued.title", "access.token.named",
      "access.web.port", "access.web.enable.port", "mainMenu.window.zoom",
      "cli.controller.show.label.input", "cli.explain.area", "cli.explain.area.endpoint",
      "common.status", "console.output", "console.stream", "developer.packetColumnData",
      "inputTest.home", "inputTest.menu",
      "keyboard.capsLock", "keyboard.meta",
      "keyboard.control", "keyboard.escape", "keyboard.alt", "keyboard.return", "keyboard.shift",
      "keyboard.tab", "mapping.guide", "motion.calibration.offset", "profiles.physical.motor",
      "profiles.stick.horizontal",
      "profiles.target", "profiles.trackball.enabled", "profiles.turbo",
      "shortcuts.controller.model",
    ],
    "it-IT": [
      "access.token.issued.title", "access.token.named",
      "mainMenu.controller", "mainMenu.file", "mainMenu.window.zoom",
      "cli.access.status.socket", "cli.controller.show.label.input",
      "cli.controller.show.label.record", "common.controller", "console.output",
      "developer.controller", "developer.controllerDetails",
      "inputTest.home", "inputTest.menu", "mapping.start", "motion.calibration.offset",
      "profiles.sectionTouch",
      "profiles.trackball.enabled", "profiles.turbo", "shortcuts.controller.type",
      "shortcuts.parameter.controller",
    ],
    "ja-JP": [
      "keyboard.capsLock", "keyboard.escape", "keyboard.alt", "keyboard.return",
      "keyboard.shift",
    ],
    "ko-KR": [
      "keyboard.capsLock", "keyboard.meta", "keyboard.control", "keyboard.escape",
      "keyboard.alt", "keyboard.return", "keyboard.shift",
    ],
    "nl-NL": [
      "library.field.transport", "access.details", "library.details",
      "access.token.issued.title", "access.token.named", "access.tokens", "library.mods",
      "mainMenu.window.zoom",
      "area.controllers.title", "menuBar.controllers",
      "mainMenu.controller", "mainMenu.help", "menuBar.help",
      "cli.access.status.socket", "cli.controller.show.label.protocol",
      "cli.controller.show.label.record", "cli.controller.show.label.rumble",
      "cli.status.label.controllers", "cli.status.label.service", "common.controller",
      "common.protocol", "common.status",
      "common.stop", "console.stream", "developer.controller",
      "developer.controllerDetails", "developer.packetColumnBytes", "developer.route",
      "inputTest.home", "inputTest.menu", "inputTest.rumble", "keyboard.capsLock",
      "keyboard.meta", "keyboard.control",
      "keyboard.escape", "keyboard.alt", "keyboard.return", "keyboard.shift", "keyboard.tab",
      "mapping.guide", "mapping.physicalRumble", "mapping.start", "motion.calibration.offset",
      "profiles.activator", "profiles.physical.effect",
      "profiles.physical.motor", "profiles.sectionSticks", "profiles.sectionTriggers",
      "profiles.stick.source", "profiles.trackball.enabled", "profiles.trigger.source",
      "profiles.turbo", "settings.controllers", "settings.updates", "shortcuts.controller.model",
      "shortcuts.controller.type", "shortcuts.parameter.controller",
    ],
    "pt-BR": [
      "access.token.issued.title", "access.token.named",
      "access.tokens", "library.mods",
      "mainMenu.window.zoom",
      "capture.linear", "common.status", "developer.packetColumnBytes",
      "inputTest.menu", "keyboard.control",
      "profiles.motion.local", "profiles.physical.motor", "profiles.stick.horizontal",
      "profiles.stick.vertical", "profiles.trackball.enabled", "profiles.turbo",
    ],
    "ru-RU": [
      "keyboard.capsLock", "keyboard.meta", "keyboard.control", "keyboard.delete",
      "keyboard.escape", "keyboard.alt", "keyboard.return", "keyboard.shift", "keyboard.tab",
      "mapping.guide",
    ],
    "th-TH": [
      "inputTest.home", "keyboard.capsLock", "keyboard.meta", "keyboard.control",
      "keyboard.delete", "keyboard.escape", "keyboard.forwardDelete", "keyboard.alt",
      "keyboard.pageDown", "keyboard.pageUp", "keyboard.return", "keyboard.shift",
      "keyboard.space", "keyboard.tab",
    ],
    "tr-TR": [
      "keyboard.control", "keyboard.escape", "keyboard.alt", "keyboard.return", "keyboard.shift",
      "keyboard.tab", "profiles.physical.motor", "profiles.trackball.enabled", "profiles.turbo",
      "shortcuts.controller.model",
    ],
    "vi-VN": [
      "cli.access.status.socket", "inputTest.home", "inputTest.menu", "keyboard.capsLock",
      "keyboard.meta", "keyboard.control", "keyboard.delete", "keyboard.escape",
      "keyboard.alt", "keyboard.pageDown", "keyboard.pageUp", "keyboard.return",
      "keyboard.shift", "keyboard.tab", "mapping.guide", "profiles.trackball.enabled",
      "profiles.turbo", "access.token.issued.title", "access.token.named",
    ],
    "zh-CN": ["keyboard.alt", "keyboard.shift"],
    "zh-TW": ["keyboard.escape", "keyboard.alt"],
  ]

  static func allowedSourceIdenticalEnglishProseKeys(for localization: String) -> Set<String> {
    let terms =
      sourceIdenticalTermsByLocale.first {
        $0.key.caseInsensitiveCompare(localization) == .orderedSame
      }?.value ?? []
    return nonLinguisticSourceIdenticalKeys.union(terms)
  }

  static func keys(for localization: String) -> Set<String> {
    var result = stringsData(for: localization).map { Set(parseStrings($0).keys) } ?? []
    result.formUnion(stringsDictionary(for: localization).keys)
    return result
  }

  static func placeholderSignatures(for localization: String) -> [String: [String]] {
    var result =
      stringsData(for: localization).map {
        parseStrings($0).mapValues { placeholderSignature(in: $0) }
      } ?? [:]
    for (key, value) in stringsDictionary(for: localization) {
      var strings: [String] = []
      collectPluralStrings(value, into: &strings)
      result[key] = strings.flatMap { placeholderSignature(in: $0) }.sorted()
    }
    return result
  }

  static func pluralCategories(for localization: String) -> [String: Set<String>] {
    stringsDictionary(for: localization).mapValues(collectPluralCategories)
  }

  static func sourceIdenticalEnglishProseKeys(for localization: String) -> Set<String> {
    let sourceStrings = stringsData(for: Localization.sourceLocalization).map(parseStrings) ?? [:]
    let localizedStrings = stringsData(for: localization).map(parseStrings) ?? [:]
    var result: Set<String> = Set(
      localizedStrings.compactMap { key, value in
        guard sourceStrings[key] == value, isEnglishProse(value) else { return nil }
        return key
      }
    )

    let sourcePlurals = stringsDictionary(for: Localization.sourceLocalization)
    let localizedPlurals = stringsDictionary(for: localization)
    for (key, localizedValue) in localizedPlurals {
      guard let sourceValue = sourcePlurals[key] else { continue }
      var sourceValues: [String] = []
      var localizedValues: [String] = []
      collectPluralStrings(sourceValue, into: &sourceValues)
      collectPluralStrings(localizedValue, into: &localizedValues)
      if zip(sourceValues, localizedValues).contains(where: { source, localized in
        source == localized && isEnglishProse(source)
      }) {
        result.insert(key)
      }
    }
    return result
  }

  /// Source texts that one word may translate in any language.
  private static let sharedTranslationSourceGroups: [Set<String>] = [
    ["deactivated", "disabled", "off"], ["delete", "remove", "uninstall"],
    ["close", "dismiss", "off", "turn off"],
  ]

  /// Keys whose value starts like a subtitle line (`- Yes.`) where the source has no `-` token.
  static func dialogueDashKeys(for localization: String) -> Set<String> {
    let sourceStrings = stringsData(for: Localization.sourceLocalization).map(parseStrings) ?? [:]
    let localizedStrings = stringsData(for: localization).map(parseStrings) ?? [:]
    return Set(
      localizedStrings.compactMap { key, value in
        guard value.range(of: #"^\s*[-–—]\s"#, options: .regularExpression) != nil,
          let source = sourceStrings[key],
          source.range(of: #"(^|\s)-(\s|$)"#, options: .regularExpression) == nil
        else { return nil }
        return key
      }
    )
  }

  /// Values shared by three or more different source texts, the shape of a copy-paste error.
  static func sharedValueCollisions(for localization: String) -> [String: Set<String>] {
    let sourceStrings = stringsData(for: Localization.sourceLocalization).map(parseStrings) ?? [:]
    let localizedStrings = stringsData(for: localization).map(parseStrings) ?? [:]
    let keysByValue = Dictionary(grouping: localizedStrings.keys) { localizedStrings[$0] ?? "" }
    return keysByValue.filter { _, keys in
      let sources = Set(keys.compactMap { sourceStrings[$0].map(normalizedSource) })
      return sources.count >= 3
        && !sharedTranslationSourceGroups.contains { sources.isSubset(of: $0) }
    }.mapValues(Set.init)
  }

  private static func normalizedSource(_ value: String) -> String {
    value.replacingOccurrences(of: #"[.…:]+$"#, with: "", options: .regularExpression).lowercased()
  }

  private static func resourceData(for localization: String, extension: String) -> Data? {
    guard
      let path = Localization.moduleBundle.path(
        forResource: "Localizable",
        ofType: `extension`,
        inDirectory: "\(localization).lproj"
      )
    else { return nil }
    return try? Data(contentsOf: URL(fileURLWithPath: path))
  }

  private static func stringsData(for localization: String) -> Data? {
    resourceData(for: localization, extension: "strings")
  }

  private static func stringsDictionary(for localization: String) -> [String: Any] {
    guard let data = resourceData(for: localization, extension: "stringsdict"),
      let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let dictionary = value as? [String: Any]
    else { return [:] }
    return dictionary
  }

  private static func parseStrings(_ data: Data) -> [String: String] {
    guard let text = String(data: data, encoding: .utf8) else { return [:] }
    let pattern = #""((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    var result: [String: String] = [:]
    expression.enumerateMatches(in: text, range: range) { match, _, _ in
      guard let match, let keyRange = Range(match.range(at: 1), in: text),
        let valueRange = Range(match.range(at: 2), in: text)
      else { return }
      result[String(text[keyRange])] = String(text[valueRange])
    }
    return result
  }

  private static func collectPluralStrings(_ value: Any, into strings: inout [String]) {
    if let string = value as? String {
      strings.append(string)
      return
    }
    guard let dictionary = value as? [String: Any] else { return }
    for (key, child) in dictionary where !key.hasPrefix("NSString") {
      collectPluralStrings(child, into: &strings)
    }
  }

  private static func collectPluralCategories(_ value: Any) -> Set<String> {
    guard let dictionary = value as? [String: Any] else { return [] }
    if dictionary["NSStringFormatSpecTypeKey"] as? String == "NSStringPluralRuleType" {
      return Set(dictionary.keys.filter { !$0.hasPrefix("NSString") })
    }
    return dictionary.values.reduce(into: Set<String>()) { result, child in
      result.formUnion(collectPluralCategories(child))
    }
  }

  private static func placeholderSignature(in value: String) -> [String] {
    let pattern = #"%(?:[0-9]+\$)?[-+0-9.#]*[@a-zA-Z]"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.matches(in: value, range: range).compactMap { match in
      Range(match.range, in: value).map { String(value[$0]) }
    }
  }

  private static func isEnglishProse(_ value: String) -> Bool {
    let withoutPlaceholders = value.replacingOccurrences(
      of: #"%(?:#@\w+@|(?:[0-9]+\$)?[-+0-9.#]*[@a-zA-Z])"#,
      with: "",
      options: .regularExpression
    )
    return withoutPlaceholders.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil
  }
}
