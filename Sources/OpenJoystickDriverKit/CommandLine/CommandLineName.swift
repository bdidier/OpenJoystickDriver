/// The command-line spelling of an UpperCamelCase document value.
///
/// A run of capitals and digits is one acronym. A word starts at a capital that follows a lowercase
/// letter, and at a capital that is followed by a lowercase letter; the words are lowercased and
/// joined with `-`. `HIDDescriptor` is `hid-descriptor`, `XboxGIP` is `xbox-gip`, `W3C` is `w3c`,
/// `OJDGenericGamepad` is `ojd-generic-gamepad` and `VendorPS3ThirdParty` is
/// `vendor-ps3-third-party`: a digit stays with the word before it.
///
/// An argument selects the case whose spelling equals it, so no per-type table exists. Two values
/// of one type must not share a spelling; `collisions(in:)` reports any that do.
public enum CommandLineName {
  /// The lowercase kebab-case spelling of `value`.
  public static func kebab(_ value: String) -> String {
    var result = ""
    let characters = Array(value)
    for (index, character) in characters.enumerated() {
      if character.isUppercase, index > 0 {
        let next = index + 1 < characters.count ? characters[index + 1] : nil
        if characters[index - 1].isLowercase || (next?.isLowercase ?? false) {
          result.append("-")
        }
      }
      result.append(Character(character.lowercased()))
    }
    return result
  }

  /// The kebab-case spelling of `value` in lowerCamelCase, the shape a catalog key segment takes:
  /// `SonyDualShock4` is `sonyDualShock4`, `EnhancedHID` is `enhancedHid` and `BluetoothLE` is
  /// `bluetoothLe`.
  public static func keySegment(_ value: String) -> String {
    kebab(value).split(separator: "-").enumerated().map { index, word in
      index == 0 ? String(word) : word.prefix(1).uppercased() + word.dropFirst()
    }.joined()
  }

  /// The case of `Value` whose raw value spells `argument` on the command line, or `nil` when no
  /// case does.
  public static func value<Value: CaseIterable & RawRepresentable>(
    of argument: String,
    in _: Value.Type = Value.self
  ) -> Value? where Value.RawValue == String {
    Value.allCases.first { kebab($0.rawValue) == argument }
  }

  /// The groups of raw values of `Value` that share one command-line spelling; empty when every
  /// case can be selected.
  public static func collisions<Value: CaseIterable & RawRepresentable>(
    in _: Value.Type = Value.self
  ) -> [[String]] where Value.RawValue == String {
    Dictionary(grouping: Value.allCases.map(\.rawValue), by: kebab)
      .values.filter { $0.count > 1 }
      .map { $0.sorted() }
      .sorted { $0.joined() < $1.joined() }
  }
}
