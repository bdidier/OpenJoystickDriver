import Foundation
import WebRTCBridgeCore

let usage = """
  usage: ojd-webrtc-bridge --role host|player [--signal offer|answer] [--socket PATH]
         [--token-name NAME] [--controller ID] [--persona Generic|SdlCompatible]
         [--ice-server URL]...
  Set OJD_TOKEN to the token that `ojd access grant --token NAME` printed.
  The offer and the answer are one line each: the bridge prints its own on stdout and reads the
  peer's from stdin. The player offers by default and the host answers.
  """

func fail(_ text: String) -> Never {
  FileHandle.standardError.write(Data((text + "\n").utf8))
  exit(1)
}

let options: [String: [String]] = {
  var parsed: [String: [String]] = [:]
  var arguments = CommandLine.arguments.dropFirst()
  while let name = arguments.popFirst() {
    guard name.hasPrefix("--"), let value = arguments.popFirst() else { fail(usage) }
    parsed[String(name.dropFirst(2)), default: []].append(value)
  }
  return parsed
}()
guard let role = options["role"]?.first, role == "host" || role == "player" else { fail(usage) }
guard let token = ProcessInfo.processInfo.environment["OJD_TOKEN"], !token.isEmpty else {
  fail("Set OJD_TOKEN to the endpoint token.")
}
let signal =
  SignalingRole(rawValue: options["signal"]?.first ?? (role == "player" ? "offer" : "answer"))
guard let signal else { fail(usage) }

func socketPath() -> String {
  if let path = options["socket"]?.first { return path }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["ojd", "--json", "access", "status"]
  let pipe = Pipe()
  process.standardOutput = pipe
  guard (try? process.run()) != nil else { fail("Cannot run `ojd`; pass --socket PATH.") }
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  guard let status = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let path = status["socketPath"] as? String
  else { fail("`ojd --json access status` gave no socketPath; pass --socket PATH.") }
  return path
}

func readPeerBlob() -> String {
  FileHandle.standardError.write(Data("Paste the peer's blob, then press Return.\n".utf8))
  guard let line = readLine(), !line.isEmpty else { fail("No blob on stdin.") }
  return line
}

func run() async throws {
  let link = try PeerLink(role: signal, iceServers: options["ice-server"] ?? [])
  if signal == .offer {
    print(try await link.localBlob())
    fflush(stdout)
    try await link.accept(readPeerBlob())
  } else {
    try await link.accept(readPeerBlob())
    print(try await link.localBlob())
    fflush(stdout)
  }
  await link.waitUntilOpen()
  let credentials = EndpointCredentials(
    socketPath: socketPath(),
    token: token,
    tokenName: options["token-name"]?.first ?? "bridge"
  )
  let ended = AsyncStream<Void>.makeStream()
  let report: @Sendable (Error?) -> Void = { error in
    if let error { FileHandle.standardError.write(Data("\(error)\n".utf8)) }
    ended.continuation.yield()
  }
  if role == "host" {
    let bridge = HostBridge(link: link, persona: options["persona"]?.first ?? "Generic")
    bridge.onEnd = report
    try bridge.start(credentials)
  } else {
    let bridge = PlayerBridge(link: link, controller: options["controller"]?.first)
    bridge.onRumble = { line in
      if let data = try? JSONSerialization.data(withJSONObject: line),
        let text = String(data: data, encoding: .utf8)
      {
        print(text)
        fflush(stdout)
      }
    }
    bridge.onEnd = report
    try bridge.start(credentials)
  }
  for await _ in ended.stream { break }
  link.close()
}

do { try await run() } catch { fail("\(error)") }
