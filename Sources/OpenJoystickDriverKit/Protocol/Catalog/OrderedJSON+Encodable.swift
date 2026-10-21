import Foundation

extension OrderedJSON: Encodable {
  /// Hands the value to an ``OrderedJSONEncoder``, which writes it as it is: members in their
  /// order and a number as its text. Any other `Encoder` throws, because it would sort the members
  /// or re-encode a number.
  public func encode(to encoder: any Encoder) throws {
    guard let writer = encoder as? OrderedJSONEncoder.Writer else {
      throw EncodingError.invalidValue(
        self,
        .init(
          codingPath: encoder.codingPath,
          debugDescription: "OrderedJSON is encoded by OrderedJSONEncoder only"
        )
      )
    }
    writer.node.value = .leaf(self)
  }
}

/// An `Encoder` that builds an ``OrderedJSON``. The members of a Swift value are sorted by name,
/// as `JSONEncoder` sorts them with `.sortedKeys`, and an embedded ``OrderedJSON`` is kept as it
/// is, so a record keeps its member order and the text of its numbers.
public struct OrderedJSONEncoder {
  public init() {}

  /// The JSON value `value` encodes to.
  ///
  /// A `Double` or `Float` that is not finite throws, as JSON cannot hold it. A value that writes
  /// nothing encodes to an empty object.
  public func encode(_ value: some Encodable) throws -> OrderedJSON {
    try Self.node(value, at: []).resolved()
  }

  /// The value being built at one place of the document.
  final class Node {
    enum Value {
      case unset
      case object([String: Node])
      case array([Node])
      case leaf(OrderedJSON)
    }

    var value = Value.unset

    func resolved() -> OrderedJSON {
      switch value {
      case .unset: return .object([])
      case .leaf(let json): return json
      case .array(let items): return .array(items.map { $0.resolved() })
      case .object(let members):
        return .object(
          members.sorted { $0.key < $1.key }.map { .init(key: $0.key, value: $0.value.resolved()) }
        )
      }
    }
  }

  struct Key: CodingKey {
    let stringValue: String
    let intValue: Int?
    init(stringValue: String) {
      self.stringValue = stringValue
      intValue = nil
    }
    init(intValue: Int) {
      stringValue = String(intValue)
      self.intValue = intValue
    }
  }

  final class Writer: Encoder {
    let node: Node
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(node: Node, codingPath: [any CodingKey]) {
      self.node = node
      self.codingPath = codingPath
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
      if case .unset = node.value { node.value = .object([:]) }
      guard case .object = node.value else {
        preconditionFailure("a keyed container over a value that is not an object")
      }
      return KeyedEncodingContainer(KeyedWriter<Key>(node: node, codingPath: codingPath))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
      if case .unset = node.value { node.value = .array([]) }
      guard case .array = node.value else {
        preconditionFailure("an unkeyed container over a value that is not an array")
      }
      return UnkeyedWriter(node: node, codingPath: codingPath)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
      SingleWriter(node: node, codingPath: codingPath)
    }
  }

  /// The JSON number for `integer`.
  private static func number(_ integer: some BinaryInteger) -> OrderedJSON {
    .number(String(integer))
  }

  /// The JSON number for `value`, as `JSONEncoder` writes it: the shortest text that reads back
  /// as `value`, without a trailing `.0`.
  private static func number<Value: BinaryFloatingPoint>(
    _ value: Value,
    at codingPath: [any CodingKey]
  ) throws -> OrderedJSON where Value: CustomStringConvertible {
    guard value.isFinite else {
      throw EncodingError.invalidValue(
        value,
        .init(codingPath: codingPath, debugDescription: "JSON cannot hold \(value)")
      )
    }
    let text = value.description
    return .number(text.hasSuffix(".0") ? String(text.dropLast(2)) : text)
  }

  /// Encodes `value` into a new node.
  private static func node(
    _ value: some Encodable,
    at codingPath: [any CodingKey]
  ) throws -> Node {
    let node = Node()
    if let json = try foundationValue(value, at: codingPath) {
      node.value = .leaf(json)
    } else {
      try value.encode(to: Writer(node: node, codingPath: codingPath))
    }
    return node
  }

  /// The JSON that `JSONEncoder` writes for a `Data`, a `Decimal` or a `URL`, whose own
  /// `encode(to:)` writes another shape: `Data` as base64 text, `Decimal` as a number and `URL` as
  /// its text. Any other value is nil.
  private static func foundationValue(
    _ value: some Encodable,
    at codingPath: [any CodingKey]
  ) throws -> OrderedJSON? {
    switch value {
    case let data as Data: return .string(data.base64EncodedString())
    case let url as URL: return .string(url.absoluteString)
    case let decimal as Decimal:
      guard decimal.isFinite else {
        throw EncodingError.invalidValue(
          decimal,
          .init(codingPath: codingPath, debugDescription: "JSON cannot hold \(decimal)")
        )
      }
      return .number(decimal.description)
    default: return nil
    }
  }

  private static func leaf(_ json: OrderedJSON) -> Node {
    let node = Node()
    node.value = .leaf(json)
    return node
  }

  private struct KeyedWriter<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let node: Node
    let codingPath: [any CodingKey]

    private func set(_ key: Key, _ member: Node) {
      guard case .object(var members) = node.value else { return }
      members[key.stringValue] = member
      node.value = .object(members)
    }

    private func set(_ key: Key, _ json: OrderedJSON) { set(key, OrderedJSONEncoder.leaf(json)) }

    func encodeNil(forKey key: Key) throws { set(key, .null) }
    func encode(_ value: Bool, forKey key: Key) throws { set(key, .bool(value)) }
    func encode(_ value: String, forKey key: Key) throws { set(key, .string(value)) }
    func encode(_ value: Double, forKey key: Key) throws {
      set(key, try OrderedJSONEncoder.number(value, at: codingPath + [key]))
    }
    func encode(_ value: Float, forKey key: Key) throws {
      set(key, try OrderedJSONEncoder.number(value, at: codingPath + [key]))
    }
    func encode(_ value: Int, forKey key: Key) throws { set(key, OrderedJSONEncoder.number(value)) }
    func encode(_ value: Int8, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    func encode(_ value: Int16, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    func encode(_ value: Int32, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    func encode(_ value: Int64, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    func encode(_ value: UInt, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    func encode(_ value: UInt8, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    func encode(_ value: UInt16, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    func encode(_ value: UInt32, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    func encode(_ value: UInt64, forKey key: Key) throws {
      set(key, OrderedJSONEncoder.number(value))
    }
    func encode<Value: Encodable>(_ value: Value, forKey key: Key) throws {
      set(key, try OrderedJSONEncoder.node(value, at: codingPath + [key]))
    }

    func nestedContainer<NestedKey: CodingKey>(
      keyedBy keyType: NestedKey.Type,
      forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
      let child = Node()
      set(key, child)
      return Writer(node: child, codingPath: codingPath + [key]).container(keyedBy: keyType)
    }

    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
      let child = Node()
      set(key, child)
      return Writer(node: child, codingPath: codingPath + [key]).unkeyedContainer()
    }

    func superEncoder() -> any Encoder { superEncoder(named: "super") }
    func superEncoder(forKey key: Key) -> any Encoder { superEncoder(named: key.stringValue) }

    private func superEncoder(named name: String) -> any Encoder {
      let child = Node()
      guard case .object(var members) = node.value else { preconditionFailure("not an object") }
      members[name] = child
      node.value = .object(members)
      return Writer(
        node: child,
        codingPath: codingPath + [OrderedJSONEncoder.Key(stringValue: name)]
      )
    }
  }

  private struct UnkeyedWriter: UnkeyedEncodingContainer {
    let node: Node
    let codingPath: [any CodingKey]

    var count: Int {
      guard case .array(let items) = node.value else { return 0 }
      return items.count
    }

    private var nextPath: [any CodingKey] { codingPath + [Key(intValue: count)] }

    private func append(_ item: Node) {
      guard case .array(var items) = node.value else { return }
      items.append(item)
      node.value = .array(items)
    }

    private func append(_ json: OrderedJSON) { append(OrderedJSONEncoder.leaf(json)) }

    mutating func encodeNil() throws { append(.null) }
    mutating func encode(_ value: Bool) throws { append(.bool(value)) }
    mutating func encode(_ value: String) throws { append(.string(value)) }
    mutating func encode(_ value: Double) throws {
      append(try OrderedJSONEncoder.number(value, at: nextPath))
    }
    mutating func encode(_ value: Float) throws {
      append(try OrderedJSONEncoder.number(value, at: nextPath))
    }
    mutating func encode(_ value: Int) throws { append(OrderedJSONEncoder.number(value)) }
    mutating func encode(_ value: Int8) throws { append(OrderedJSONEncoder.number(value)) }
    mutating func encode(_ value: Int16) throws { append(OrderedJSONEncoder.number(value)) }
    mutating func encode(_ value: Int32) throws { append(OrderedJSONEncoder.number(value)) }
    mutating func encode(_ value: Int64) throws { append(OrderedJSONEncoder.number(value)) }
    mutating func encode(_ value: UInt) throws { append(OrderedJSONEncoder.number(value)) }
    mutating func encode(_ value: UInt8) throws { append(OrderedJSONEncoder.number(value)) }
    mutating func encode(_ value: UInt16) throws { append(OrderedJSONEncoder.number(value)) }
    mutating func encode(_ value: UInt32) throws { append(OrderedJSONEncoder.number(value)) }
    mutating func encode(_ value: UInt64) throws { append(OrderedJSONEncoder.number(value)) }
    mutating func encode<Value: Encodable>(_ value: Value) throws {
      append(try OrderedJSONEncoder.node(value, at: nextPath))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
      keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
      let path = nextPath
      let child = Node()
      append(child)
      return Writer(node: child, codingPath: path).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
      let path = nextPath
      let child = Node()
      append(child)
      return Writer(node: child, codingPath: path).unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
      let path = nextPath
      let child = Node()
      append(child)
      return Writer(node: child, codingPath: path)
    }
  }

  private struct SingleWriter: SingleValueEncodingContainer {
    let node: Node
    let codingPath: [any CodingKey]

    private func set(_ json: OrderedJSON) { node.value = .leaf(json) }

    func encodeNil() throws { set(.null) }
    func encode(_ value: Bool) throws { set(.bool(value)) }
    func encode(_ value: String) throws { set(.string(value)) }
    func encode(_ value: Double) throws {
      set(try OrderedJSONEncoder.number(value, at: codingPath))
    }
    func encode(_ value: Float) throws {
      set(try OrderedJSONEncoder.number(value, at: codingPath))
    }
    func encode(_ value: Int) throws { set(OrderedJSONEncoder.number(value)) }
    func encode(_ value: Int8) throws { set(OrderedJSONEncoder.number(value)) }
    func encode(_ value: Int16) throws { set(OrderedJSONEncoder.number(value)) }
    func encode(_ value: Int32) throws { set(OrderedJSONEncoder.number(value)) }
    func encode(_ value: Int64) throws { set(OrderedJSONEncoder.number(value)) }
    func encode(_ value: UInt) throws { set(OrderedJSONEncoder.number(value)) }
    func encode(_ value: UInt8) throws { set(OrderedJSONEncoder.number(value)) }
    func encode(_ value: UInt16) throws { set(OrderedJSONEncoder.number(value)) }
    func encode(_ value: UInt32) throws { set(OrderedJSONEncoder.number(value)) }
    func encode(_ value: UInt64) throws { set(OrderedJSONEncoder.number(value)) }
    func encode<Value: Encodable>(_ value: Value) throws {
      node.value = try OrderedJSONEncoder.node(value, at: codingPath).value
    }
  }
}
