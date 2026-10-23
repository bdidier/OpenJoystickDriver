import AppKit
import GameController

// A snake game that reads controllers only through Apple's GameController framework, so a pad
// that plays it works in GameController games. The D-pad or left stick steers, A restarts after a
// crash, and Menu pauses. Each connection and button press is also printed to standard output.

let columns = 20
let rows = 20
let cellSize: CGFloat = 24

struct Cell: Hashable {
  var x: Int
  var y: Int
}

final class SnakeView: NSView {
  private var snake = [Cell(x: 10, y: 10)]
  private var heading = Cell(x: 1, y: 0)
  private var nextHeading = Cell(x: 1, y: 0)
  private var food = Cell(x: 5, y: 5)
  private(set) var crashed = false
  var paused = false
  var controllerName = "No controller. Connect one."
  var lastButton = ""

  override var isFlipped: Bool { true }

  /// Turns the snake, except straight back into itself.
  func steer(_ direction: Cell) {
    guard direction.x != -heading.x || direction.y != -heading.y else { return }
    nextHeading = direction
  }

  func restart() {
    snake = [Cell(x: 10, y: 10)]
    heading = Cell(x: 1, y: 0)
    nextHeading = heading
    crashed = false
    placeFood()
    needsDisplay = true
  }

  func step() {
    guard !crashed, !paused else { return }
    heading = nextHeading
    let head = Cell(x: snake[0].x + heading.x, y: snake[0].y + heading.y)
    if !(0..<columns).contains(head.x) || !(0..<rows).contains(head.y) || snake.contains(head) {
      crashed = true
      print("crash: score \(snake.count - 1)")
    } else {
      snake.insert(head, at: 0)
      if head == food { placeFood() } else { snake.removeLast() }
    }
    needsDisplay = true
  }

  private func placeFood() {
    let free = (0..<columns).flatMap { x in (0..<rows).map { Cell(x: x, y: $0) } }
      .filter { !snake.contains($0) }
    if let cell = free.randomElement() { food = cell }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.black.setFill()
    bounds.fill()
    fill(food, NSColor.systemRed)
    for cell in snake { fill(cell, NSColor.systemGreen) }
    var lines = [controllerName, "Score \(snake.count - 1)"]
    if !lastButton.isEmpty { lines.append("Last button: \(lastButton)") }
    if crashed { lines.append("Crashed. Press A to play again.") }
    if paused { lines.append("Paused. Press Menu to go on.") }
    let attributes: [NSAttributedString.Key: Any] = [
      .foregroundColor: NSColor.white,
      .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
    ]
    for (index, line) in lines.enumerated() {
      NSAttributedString(string: line, attributes: attributes)
        .draw(at: NSPoint(x: 6, y: 4 + CGFloat(index) * 16))
    }
  }

  private func fill(_ cell: Cell, _ color: NSColor) {
    color.setFill()
    NSRect(
      x: CGFloat(cell.x) * cellSize,
      y: CGFloat(cell.y) * cellSize,
      width: cellSize,
      height: cellSize
    )
    .insetBy(dx: 1, dy: 1).fill()
  }
}

/// The direction a D-pad or stick points at when it is pushed past half way, with up as negative
/// y because the view's origin is at the top.
func direction(x: Float, y: Float) -> Cell? {
  if abs(x) > abs(y), abs(x) > 0.5 { return Cell(x: x > 0 ? 1 : -1, y: 0) }
  if abs(y) > 0.5 { return Cell(x: 0, y: y > 0 ? -1 : 1) }
  return nil
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let view = SnakeView(
    frame: NSRect(x: 0, y: 0, width: CGFloat(columns) * cellSize, height: CGFloat(rows) * cellSize)
  )
  private var window: NSWindow?
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: view.frame,
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "GameController Snake"
    window.contentView = view
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate(ignoringOtherApps: true)

    // Notifications, the timer and GameController handlers all run on the main queue.
    GCController.shouldMonitorBackgroundEvents = true
    // GameController posts a notification for each change; the handler reads the current list.
    observers = [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect].map {
      NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { self.attachControllers() }
      }
    }
    attachControllers()
    timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
      MainActor.assumeIsolated { self.view.step() }
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  /// Attaches every connected controller and names the last one, or says that none is connected.
  private func attachControllers() {
    let controllers = GCController.controllers()
    print("controllers: \(controllers.count)")
    view.controllerName = "No controller. Connect one."
    view.needsDisplay = true
    controllers.forEach(attach)
  }

  private func attach(_ controller: GCController) {
    let name = "\(controller.vendorName ?? "Controller") (\(controller.productCategory))"
    print("connect: \(name)")
    view.controllerName = name
    view.needsDisplay = true
    guard let pad = controller.extendedGamepad else {
      view.controllerName = "\(name): no extended gamepad profile"
      return
    }
    let view = view
    let steer: (Float, Float) -> Void = { x, y in
      guard let turn = direction(x: x, y: y) else { return }
      MainActor.assumeIsolated { view.steer(turn) }
    }
    pad.dpad.valueChangedHandler = { _, x, y in steer(x, y) }
    pad.leftThumbstick.valueChangedHandler = { _, x, y in steer(x, y) }
    let restart = pad.buttonA
    let pause = pad.buttonMenu
    for button in controller.physicalInputProfile.allButtons {
      let label = button.localizedName ?? button.aliases.min() ?? "Button"
      button.pressedChangedHandler = { button, _, pressed in
        guard pressed else { return }
        print("button: \(label)")
        MainActor.assumeIsolated {
          view.lastButton = label
          if button === restart, view.crashed { view.restart() }
          if button === pause { view.paused.toggle() }
          view.needsDisplay = true
        }
      }
    }
  }
}

// Line buffering keeps each printed event when standard output is a pipe or a file.
setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
