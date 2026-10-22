import Foundation

extension OrderedJSON {
  /// The members of an object, or nil for any other value.
  var members: [Member]? {
    guard case .object(let members) = self else { return nil }
    return members
  }

  /// The value of the member `key` of an object, or nil when this is not an object or has no
  /// such member.
  subscript(key: String) -> Self? {
    members?.first { $0.key == key }?.value
  }

  /// The text of a string value.
  var string: String? {
    guard case .string(let text) = self else { return nil }
    return text
  }

  /// A JSON integer: digits with an optional minus sign. A number written with a fraction or an
  /// exponent, such as `1.0` or `1e3`, a boolean, and a string are not.
  var integer: Int? {
    guard case .number(let text) = self else { return nil }
    return Int(text)
  }

  /// The value as `JSONSerialization` reads it, for code that reads typed fields. A number
  /// becomes an `NSNumber` there, so the result is never written back as record text.
  func foundationValue() throws -> Any {
    try JSONSerialization.jsonObject(
      with: Data(compact().utf8),
      options: .fragmentsAllowed
    )
  }

  /// Whether the two values are the same JSON value: object members in any order, and numbers by
  /// value, so `8E-2` and `0.08` are the same. A number that `Decimal` cannot read compares by
  /// its text.
  func hasSameValue(as other: Self) -> Bool {
    switch (self, other) {
    case (.object(let left), .object(let right)):
      guard left.count == right.count else { return false }
      return left.allSatisfy { member in
        other[member.key].map { member.value.hasSameValue(as: $0) } ?? false
      }
    case (.array(let left), .array(let right)):
      return left.count == right.count
        && zip(left, right).allSatisfy { $0.hasSameValue(as: $1) }
    case (.number(let left), .number(let right)):
      guard let first = Decimal(string: left), let second = Decimal(string: right) else {
        return left == right
      }
      return first == second
    default:
      return self == other
    }
  }
}
