import Foundation

/// Why a protocol description is invalid, in words for the person who wrote it, with the
/// catalog code that names the failure.
struct ProtocolDescriptionProblem: Error, Equatable, Sendable, CustomStringConvertible {
  let code: ErrorCode
  let detail: String

  init(_ code: ErrorCode, _ detail: String) {
    self.code = code
    self.detail = detail
  }

  var description: String { "\(code.rawValue): \(detail)" }
}

/// One family's protocol description (`Resources/Protocols/<file stem>.json`): the interface
/// signatures that bind its variants, the typed parameters its records may set, the facts its
/// driver reads (endpoints, raw USB, record sections, tuning keys, what OJD still
/// sends when macOS serves the controller), and the defaults its records layer over. Drivers read
/// these values; they hold no copy.
struct ProtocolDescription: Sendable {
  /// A parameter's declared type.
  enum ParameterType: Equatable, Sendable {
    /// `true` or absent.
    case flag
    /// One of these names.
    case enumeration([String])
    /// An object of integer fields, each within its range.
    case object([String: ClosedRange<Int>])
  }

  /// The default USB endpoint addresses of a raw-USB family.
  struct Endpoints: Equatable, Sendable {
    let input: Int
    let output: Int
  }

  /// Which variants of a family are reached through raw USB.
  enum RawUSB: Equatable, Sendable {
    case never
    case always
    case variants(Set<PhysicalProtocolVariantID>)

    func applies(to variant: PhysicalProtocolVariantID?) -> Bool {
      switch self {
      case .never: false
      case .always: true
      case .variants(let variants): variant.map(variants.contains) ?? false
      }
    }
  }

  /// A record section whose layout the family's driver reads.
  enum RecordSection: String, Sendable {
    case input
    case rumble
  }

  /// The `kind` of a protocol description.
  static let kind = "ProtocolDescription"

  let family: PhysicalProtocolID
  let endpoints: Endpoints
  let rawUSB: RawUSB
  let recordSections: Set<RecordSection>
  /// The `tuning` keys the family reads beyond `stickDeadzone` and `frameQueueCapacity` through
  /// IOHID; none when every variant is raw USB.
  let tuningKeys: Set<ControllerTuning.Key>
  /// The `tuning` keys a raw-USB variant reads beyond `stickDeadzone` and `frameQueueCapacity`.
  let rawUSBTuningKeys: Set<ControllerTuning.Key>
  /// What OJD still sends when macOS serves the controller.
  let macOSOwnedOutput: MacOSOwnedOutput
  let interfaceSignatures: [ProtocolInterfaceSignature]
  /// The parameters records of this family may set, by name.
  let parameters: [String: ParameterType]
  /// The controls every controller of the family has; a driver adds only what its record or
  /// layout makes true. Nil for a family whose controls follow its layout.
  let controls: ControllerCapabilities?
  /// The capability deltas a record of this family may declare.
  let recordCapabilities: RecordCapabilityRules
  let rumbleTemplate: RumbleOutputTemplate?
  /// The family's HID initialization writes, sent when a controller starts unless its record
  /// carries its own.
  let startupWrites: [RecordStartupWrite]
  /// The family's raw-USB initialization packets, sent when a controller starts unless its record
  /// carries its own.
  let usbStartupWrites: [USBStartupWrite]
  /// The family's keep-alive: its interval, the one place the interval is set, and the fixed
  /// writes of each run.
  let keepAlive: KeepAlive?
  /// The family's subcommand reports: the report id, the rolling counter rule and the startup
  /// requests. Only `NintendoSwitch1` has them.
  let subcommands: SubcommandPlan?
  /// The family's named packets, which a record selects by id in `protocol.initialization`.
  /// Only `XboxGIP` has them.
  let namedPackets: NamedPacketPlan?
  /// The startup attempts a raw-USB handshake makes before it fails. Only `XboxGIP` has it.
  let handshakeAttempts: Int?
  /// The most startup resends after announces before the first input. Only `XboxGIP` has it.
  let announceResendLimit: Int?
  /// The most presence inquiry resends for a receiver slot. Only `XboxXUSB` has it.
  let receiverInquiryResendLimit: Int?
  let inputLayout: ControllerInputLayout?
  /// The map every `HIDDescriptor` record layers over (``HIDUsageMap``).
  let hidUsageMap: HIDUsageMap?
  /// Descriptor shapes that select another map, first match first.
  let hidUsageShapes: [HIDUsageShape]
  let tuning: ControllerTuning?
  /// Tuning defaults by stored variant, layered over `tuning` for that variant.
  let variantTuning: [PhysicalProtocolVariantID: ControllerTuning]
  /// Rumble templates by stored variant, each overriding `rumbleTemplate` for that variant.
  let variantRumble: [PhysicalProtocolVariantID: RumbleOutputTemplate]

  /// The capability deltas a record may declare: exactly this set of present controls (or none),
  /// and rumble absent.
  struct RecordCapabilityRules: Equatable, Sendable {
    let presentControls: Set<Control>
    let rumbleAbsent: Bool

    static let none = Self(presentControls: [], rumbleAbsent: false)

    func permits(_ delta: ControllerCapabilityDelta) -> Bool {
      (delta.presentControls.isEmpty || delta.presentControls == presentControls)
        && (!delta.rumbleAbsent || rumbleAbsent)
    }
  }

  /// The defaults a controller of this family and stored variant starts from: the family's
  /// `tuning` with the variant's layered over it; nil when neither sets a key.
  func tuning(variant: PhysicalProtocolVariantID?) -> ControllerTuning? {
    let layered = (tuning ?? .none).overlaid(by: variant.flatMap { variantTuning[$0] } ?? .none)
    return layered == .none ? nil : layered
  }

  /// The rumble template a controller of this family and stored variant encodes from: the
  /// variant's own when the description sets one, otherwise the family's; nil when neither does.
  func rumbleTemplate(variant: PhysicalProtocolVariantID?) -> RumbleOutputTemplate? {
    variant.flatMap { variantRumble[$0] } ?? rumbleTemplate
  }

  /// The bundled descriptions, by family.
  static let bundled: [PhysicalProtocolID: Self] = {
    do { return try loadBundled() } catch {
      fatalError("[ProtocolDescription] Invalid protocol descriptions: \(error)")
    }
  }()

  private static func loadBundled() throws -> [PhysicalProtocolID: Self] {
    var descriptions: [PhysicalProtocolID: Self] = [:]
    for protocolID in PhysicalProtocolID.allCases {
      guard
        let url = Bundle.module.url(
          forResource: protocolID.descriptionFileStem,
          withExtension: "json"
        )
      else {
        throw ProtocolDescriptionProblem(
          .invalidProtocolDescription,
          "\(protocolID.descriptionFileStem).json is missing from the bundle"
        )
      }
      descriptions[protocolID] = try decode(
        Data(contentsOf: url),
        protocolID: protocolID,
        fileName: url.lastPathComponent
      )
    }
    return descriptions
  }

  /// Decodes one description, the file `fileName` that the bundle holds for `protocolID`.
  ///
  /// A malformed document, an unknown field and a value outside its range are E5002; a family
  /// that is not the file's is E5003; a variant that the family lacks is E5004.
  static func decode(
    _ data: Data,
    protocolID: PhysicalProtocolID,
    fileName: String
  ) throws(ProtocolDescriptionProblem) -> Self {
    let document: Document
    do {
      let decoder = JSONDecoder()
      decoder.userInfo[.startupConditionsAllowed] = true
      document = try decoder.decode(Document.self, from: data)
    } catch {
      throw ProtocolDescriptionProblem(.invalidProtocolDescription, "\(fileName): \(error)")
    }
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: document.apiVersion,
      kind: document.kind,
      expected: kind
    ) {
      throw ProtocolDescriptionProblem(
        problem.code ?? .invalidProtocolDescription,
        "\(fileName): \(problem.message)"
      )
    }
    guard document.family == protocolID.rawValue else {
      throw ProtocolDescriptionProblem(
        .protocolDescriptionFamilyMismatch,
        "\(fileName): family must be \(protocolID.rawValue)"
      )
    }
    var signatures: [ProtocolInterfaceSignature] = []
    for signature in document.interfaceSignatures {
      guard let variant = PhysicalProtocolVariantID(rawValue: signature.variant),
        protocolID.variants.contains(variant)
      else {
        throw ProtocolDescriptionProblem(
          .unknownProtocolVariant,
          "\(fileName): \(protocolID.rawValue) has no variant \(signature.variant)"
        )
      }
      signatures.append(
        ProtocolInterfaceSignature(
          protocolID: protocolID,
          variant: variant,
          interfaceClass: signature.interfaceClass,
          interfaceSubclass: signature.interfaceSubclass,
          interfaceProtocol: signature.interfaceProtocol,
          requiredInterfaceNumber: signature.interfaceNumber
        )
      )
    }
    var rawUSB = RawUSB.never
    switch document.rawUSB {
    case .none: break
    case .always: rawUSB = .always
    case .variants(let names):
      var variants: Set<PhysicalProtocolVariantID> = []
      for name in names {
        guard let variant = PhysicalProtocolVariantID(rawValue: name),
          protocolID.variants.contains(variant)
        else {
          throw ProtocolDescriptionProblem(
            .unknownProtocolVariant,
            "\(fileName): \(protocolID.rawValue) has no variant \(name)"
          )
        }
        variants.insert(variant)
      }
      rawUSB = .variants(variants)
    }
    func variant(named name: String) throws(ProtocolDescriptionProblem) -> PhysicalProtocolVariantID
    {
      guard let variant = PhysicalProtocolVariantID(rawValue: name),
        protocolID.variants.contains(variant)
      else {
        throw ProtocolDescriptionProblem(
          .unknownProtocolVariant,
          "\(fileName): \(protocolID.rawValue) has no variant \(name)"
        )
      }
      return variant
    }
    var variantTuning: [PhysicalProtocolVariantID: ControllerTuning] = [:]
    for (name, tuning) in document.defaults?.variantTuning ?? [:] {
      variantTuning[try variant(named: name)] = tuning
    }
    var variantRumble: [PhysicalProtocolVariantID: RumbleOutputTemplate] = [:]
    for (name, template) in document.defaults?.variantRumble ?? [:] {
      variantRumble[try variant(named: name)] = template
    }
    let usbStartupWrites = try resolvedUSBStartup(
      document.defaults?.session?.startup,
      namedPackets: document.defaults?.session?.namedPackets,
      fileName: fileName
    )
    let description = Self(
      family: protocolID,
      endpoints: document.endpoints,
      rawUSB: rawUSB,
      recordSections: document.recordSections,
      tuningKeys: document.tuningKeys,
      rawUSBTuningKeys: document.rawUSBTuningKeys,
      macOSOwnedOutput: document.macOSOwnedOutput,
      interfaceSignatures: signatures,
      parameters: document.parameters,
      controls: document.controls,
      recordCapabilities: document.recordCapabilities,
      rumbleTemplate: document.defaults?.session?.rumble,
      startupWrites: document.defaults?.session?.startup?.hid ?? [],
      usbStartupWrites: usbStartupWrites,
      keepAlive: document.defaults?.session?.keepAlive,
      subcommands: document.defaults?.session?.subcommands,
      namedPackets: document.defaults?.session?.namedPackets,
      handshakeAttempts: document.defaults?.session?.handshakeAttempts,
      announceResendLimit: document.defaults?.session?.announceResendLimit,
      receiverInquiryResendLimit: document.defaults?.session?.receiverInquiryResendLimit,
      inputLayout: document.defaults?.input?.layout,
      hidUsageMap: document.defaults?.input?.usageMap,
      hidUsageShapes: document.defaults?.input?.shapes ?? [],
      tuning: document.defaults?.tuning,
      variantTuning: variantTuning,
      variantRumble: variantRumble
    )
    for condition in description.startupWrites.map(\.condition)
      + description.usbStartupWrites.map(\.condition)
      + (description.keepAlive?.writes.map(\.payload.condition) ?? [])
    {
      if let problem = description.conditionProblem(condition, fileName: fileName) {
        throw problem
      }
    }
    if let violation = description.scopeViolation {
      throw ProtocolDescriptionProblem(.invalidProtocolDescription, "\(fileName): \(violation)")
    }
    return description
  }

  /// The raw-USB startup packets of `startup`: its own, or the named packets it refers to, each
  /// with the condition of its reference. A reference to a packet the description lacks fails.
  private static func resolvedUSBStartup(
    _ startup: ControllerRecordDocument.StartupList?,
    namedPackets: NamedPacketPlan?,
    fileName: String
  ) throws(ProtocolDescriptionProblem) -> [USBStartupWrite] {
    guard let startup, !startup.packets.isEmpty else { return startup?.usb ?? [] }
    var writes: [USBStartupWrite] = []
    for reference in startup.packets {
      guard let packet = namedPackets?.packet(named: reference.id) else {
        throw ProtocolDescriptionProblem(
          .invalidProtocolDescription,
          "\(fileName): startup names \(reference.id), which is not a named packet"
        )
      }
      do {
        writes.append(try packet.write.with(condition: reference.condition))
      } catch {
        throw ProtocolDescriptionProblem(
          .invalidProtocolDescription,
          "\(fileName): \(error.description)"
        )
      }
    }
    return writes
  }

  /// The fixed keep-alive writes that a controller on `variant` receives from this description.
  /// A keep-alive write has no `when`. A record's mode adds a keep-alive only for a family whose
  /// description declares none.
  func keepAliveWrites(variant: PhysicalProtocolVariantID?) -> [KeepAliveWrite] {
    (keepAlive?.writes ?? []).filter {
      $0.payload.condition.matches(variant: variant, parameters: .none)
    }
  }

  /// Why a startup write's condition names a variant the family lacks (E5004) or a parameter or
  /// value the description does not declare (E5002), or nil.
  private func conditionProblem(
    _ condition: StartupWriteCondition,
    fileName: String
  ) -> ProtocolDescriptionProblem? {
    for variant in condition.variants ?? [] where !family.variants.contains(variant) {
      return ProtocolDescriptionProblem(
        .unknownProtocolVariant,
        "\(fileName): \(family.rawValue) has no variant \(variant.rawValue)"
      )
    }
    guard let rule = condition.rule else { return nil }
    guard case .enumeration(let declared)? = parameters[rule.parameter] else {
      return ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(fileName): when names \(rule.parameter), which is not an enumeration parameter of "
          + family.rawValue
      )
    }
    for value in rule.values where !declared.contains(value) {
      return ProtocolDescriptionProblem(
        .invalidProtocolDescription,
        "\(fileName): when names \(value), which \(rule.parameter) does not declare"
      )
    }
    return nil
  }

  /// The HID startup writes of `phase` that a controller on `variant` whose record sets
  /// `parameters` receives from this description.
  func startupWrites(
    phase: StartupPhase,
    variant: PhysicalProtocolVariantID?,
    parameters: ProtocolParameters
  ) -> [RecordStartupWrite] {
    startupWrites.filter {
      $0.phase == phase && $0.condition.matches(variant: variant, parameters: parameters)
    }
  }

  /// The raw-USB startup packets that a controller on `variant` whose record sets `parameters`
  /// receives from this description.
  func usbStartupWrites(
    variant: PhysicalProtocolVariantID?,
    parameters: ProtocolParameters
  ) -> [USBStartupWrite] {
    usbStartupWrites.filter { $0.condition.matches(variant: variant, parameters: parameters) }
  }

  /// Why the defaults name something the family's driver does not read, or nil. The rule reads
  /// only this description, so it holds while the bundle is still loading.
  private var scopeViolation: String? {
    if inputLayout != nil, !recordSections.contains(.input) {
      return "an input layout applies only to a family that reads one"
    }
    if hidUsageMap != nil || !hidUsageShapes.isEmpty, family != .hidDescriptor {
      return "a HID usage map applies only to HIDDescriptor"
    }
    if rumbleTemplate != nil || !variantRumble.isEmpty, !recordSections.contains(.rumble) {
      return "rumble templates require a driver that encodes them"
    }
    if let violation = rumbleTargetViolation { return violation }
    if keepAlive != nil,
      ([rumbleTemplate].compactMap { $0 } + Array(variantRumble.values)).contains(where: {
        $0.resendIntervalMilliseconds != nil
      })
    {
      return RumbleOutputTemplate.resendWithFamilyKeepAliveProblem
    }
    if !startupWrites.isEmpty, rawUSB == .always {
      return "HID startup writes apply only to HID controllers"
    }
    if family == .xboxXID, !startupWrites.isEmpty || !usbStartupWrites.isEmpty || keepAlive != nil {
      return "XboxXID's session holds only a rumble template"
    }
    if let violation = keepAliveViolation { return violation }
    if (subcommands != nil) != (family == .nintendoSwitch1) {
      return "only NintendoSwitch1 has subcommands, and it must have them"
    }
    if namedPackets != nil, family != .xboxGIP {
      return "only XboxGIP has named packets"
    }
    if let namedPackets, !namedPackets.allIDs(startWith: "\(family.rawValue)/") {
      return "each named packet id starts with \(family.rawValue)/"
    }
    if (handshakeAttempts != nil) != (family == .xboxGIP)
      || (announceResendLimit != nil) != (family == .xboxGIP)
    {
      return "only XboxGIP has handshakeAttempts and announceResendLimit, and it must have them"
    }
    if (receiverInquiryResendLimit != nil) != (family == .xboxXUSB) {
      return "only XboxXUSB has receiverInquiryResendLimit, and it must have it"
    }
    if rawUSB == .always, !tuningKeys.isEmpty {
      return "a family that is always raw USB reads its tuning through rawUSBTuningKeys"
    }
    if rawUSB == .never, !rawUSBTuningKeys.isEmpty {
      return "rawUSBTuningKeys apply only to a family with a raw-USB variant"
    }
    if let tuning {
      let scope = tuningKeys.union(rawUSBTuningKeys).union(ControllerTuning.Key.alwaysRead)
      for key in ControllerTuning.Key.allCases
      where tuning.setKeys.contains(key) && !scope.contains(key) {
        return "\(key) is not read by the \(family.rawValue) driver"
      }
    }
    for (variant, tuning) in variantTuning.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
      let scope = tuningScope(variant: variant)
      for key in ControllerTuning.Key.allCases
      where tuning.setKeys.contains(key) && !scope.contains(key) {
        return "\(key) is not read by the \(family.rawValue):\(variant.rawValue) driver"
      }
    }
    return nil
  }

  /// Why a rumble template targets a packet kind that its variants do not use, or nil: a raw-USB
  /// variant's template is a usb packet and a HID variant's is a HID report. The flat template
  /// is checked against each variant of the family that has no template of its own; a family
  /// with no variants has the one unnamed variant.
  private var rumbleTargetViolation: String? {
    let mismatch =
      "a raw-USB variant's rumble template is a usb packet, and a HID variant's is a HID report"
    if let rumbleTemplate {
      let flatVariants: [PhysicalProtocolVariantID?] =
        family.variants.isEmpty ? [nil] : family.variants.map(Optional.some)
      for variant in flatVariants where variant.map({ variantRumble[$0] == nil }) ?? true {
        if (rumbleTemplate.report == nil) != rawUSB.applies(to: variant) { return mismatch }
      }
    }
    for (variant, template) in variantRumble.sorted(by: { $0.key.rawValue < $1.key.rawValue })
    where (template.report == nil) != rawUSB.applies(to: variant) {
      return mismatch
    }
    return nil
  }

  /// Why the keep-alive names something the family's driver does not read, or nil.
  private var keepAliveViolation: String? {
    guard let keepAlive else { return nil }
    let reads = tuningKeys.union(rawUSBTuningKeys)
    for write in keepAlive.writes {
      switch write.payload {
      case .hid where rawUSB == .always:
        return "a HID keep-alive write applies only to HID controllers"
      case .usb where rawUSB == .never:
        return "a raw-USB keep-alive write applies only to a family with a raw-USB variant"
      default: break
      }
      if let key = write.resendTuning, !reads.contains(key) || tuning?.text(of: key) == nil {
        return "resendTuning names \(key.rawValue), which the family must read and default"
      }
    }
    return nil
  }

  /// The tuning keys a controller of this family and stored variant reads: the
  /// always-read keys, and the family's `rawUSBTuningKeys` when the variant is raw USB, otherwise
  /// its `tuningKeys`.
  func tuningScope(variant: PhysicalProtocolVariantID?) -> Set<ControllerTuning.Key> {
    (rawUSB.applies(to: variant) ? rawUSBTuningKeys : tuningKeys)
      .union(ControllerTuning.Key.alwaysRead)
  }
}
