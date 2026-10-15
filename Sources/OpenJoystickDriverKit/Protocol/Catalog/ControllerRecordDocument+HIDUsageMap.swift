import Foundation

extension ControllerRecordDocument {
  /// A record's or description's `input` section, which is either a byte layout or, for
  /// `hid.descriptor`, a HID usage map. The keys decide which: `hidUsageMap` and
  /// `descriptorShapes` are usage-map keys, any other key belongs to the byte layout.
  struct Input: Decodable {
    let layout: ControllerInputLayout?
    let usageMap: HIDUsageMap?
    let shapes: [HIDUsageShape]

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let usageKeys: Set<String> = ["hidUsageMap", "descriptorShapes"]
      if Set(container.allKeys.map(\.stringValue)).isDisjoint(with: usageKeys) {
        layout = try InputLayout(from: decoder).layout
        usageMap = nil
        shapes = []
        return
      }
      try container.rejectUnknown(allowed: usageKeys)
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "input must not be empty")
        )
      }
      layout = nil
      usageMap = try container.decodeOptional(UsageMap.self, for: "hidUsageMap")?.map
      shapes =
        try container.decodeOptional([UsageShape].self, for: "descriptorShapes")?
        .map(\.shape) ?? []
      guard container.contains(DocumentKey("descriptorShapes")) == !shapes.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("descriptorShapes")],
            debugDescription: "descriptorShapes must not be empty"
          )
        )
      }
    }
  }

  struct UsageMap: Decodable {
    let map: HIDUsageMap

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["reportID", "usages"])
      let reportID = try container.decodeOptional(Int.self, for: "reportID")
      guard reportID.map({ (1...255).contains($0) }) ?? true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("reportID")],
            debugDescription: "reportID must be 1...255"
          )
        )
      }
      let usages = try container.decode([UsageEntry].self, for: "usages")
      do {
        map = try HIDUsageMap(reportID: reportID.map(UInt32.init), entries: usages.map(\.entry))
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: problem.description)
        )
      }
    }
  }

  struct UsageRef: Decodable {
    let usage: HIDUsage

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["page", "usage"])
      usage = try UsageEntry.usage(in: container, codingPath: decoder.codingPath)
    }
  }

  struct UsageEntry: Decodable {
    let entry: HIDUsageMap.Entry

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let kind = try container.decode(String.self, for: "kind")
      let usage = try Self.usage(in: container, codingPath: decoder.codingPath)
      let binding: HIDUsageMap.Binding
      switch kind {
      case "button":
        try container.rejectUnknown(allowed: ["kind", "page", "usage", "control"])
        binding = .button(try container.decode(Control.self, for: "control"))
      case "axis":
        let control = try container.decode(Control.self, for: "control")
        try container.rejectUnknown(allowed: [
          "kind", "page", "usage", "control", "inverted", "range", "deadZone",
        ])
        let deadZone = try container.decodeOptional(Double.self, for: "deadZone")
        binding = .axis(
          HIDUsageMap.Axis(
            control: control,
            isInverted: try container.decodeOptional(Bool.self, for: "inverted") ?? false,
            range: try container.decodeOptional(UsageRange.self, for: "range")?.range,
            deadZone: deadZone.map(Float.init)
          )
        )
      case "hat":
        try container.rejectUnknown(allowed: ["kind", "page", "usage", "range"])
        binding = .hat(
          HIDUsageMap.Hat(range: try container.decodeOptional(UsageRange.self, for: "range")?.range)
        )
      default:
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("kind")],
            debugDescription: "kind is button, axis or hat"
          )
        )
      }
      entry = HIDUsageMap.Entry(usage: usage, binding: binding)
    }

    static func usage(
      in container: KeyedDecodingContainer<DocumentKey>,
      codingPath: [any CodingKey]
    ) throws -> HIDUsage {
      let page = try container.decode(Int.self, for: "page")
      let usage = try container.decode(Int.self, for: "usage")
      guard (1...65_535).contains(page), (0...65_535).contains(usage) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: codingPath, debugDescription: "page is 1...65535 and usage 0...65535")
        )
      }
      return HIDUsage(usagePage: page, usage: usage)
    }
  }

  struct UsageRange: Decodable {
    let range: ClosedRange<Int>

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["min", "max"])
      let low = try container.decode(Int.self, for: "min")
      let high = try container.decode(Int.self, for: "max")
      guard Int(Int32.min)...Int(Int32.max) ~= low, Int(Int32.min)...Int(Int32.max) ~= high,
        low <= high
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "min and max are 32-bit integers with min at most max"
          )
        )
      }
      range = low...high
    }
  }

  struct UsageShape: Decodable {
    let shape: HIDUsageShape

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["present", "absent", "anyOf", "hidUsageMap"])
      func usages(_ key: String) throws -> Set<HIDUsage> {
        guard let refs = try container.decodeOptional([UsageRef].self, for: key) else { return [] }
        let set = Set(refs.map(\.usage))
        guard !refs.isEmpty, set.count == refs.count else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey(key)],
              debugDescription: "\(key) must be nonempty and unique"
            )
          )
        }
        return set
      }
      shape = HIDUsageShape(
        present: try usages("present"),
        absent: try usages("absent"),
        anyOf: try usages("anyOf"),
        map: try container.decode(UsageMap.self, for: "hidUsageMap").map
      )
      guard !shape.present.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "present is required")
        )
      }
    }
  }
}
