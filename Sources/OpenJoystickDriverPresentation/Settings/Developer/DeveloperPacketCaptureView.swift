#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct DeveloperPacketCaptureView: View {
    @ObservedObject
    var model: DeveloperToolsViewModel

    var body: some View {
      let displayedPackets = model.displayedPackets
      Section(OJDLocalized.string("ui.developer.packetCapture")) {
        captureStatus
        Picker(OJDLocalized.string("ui.developer.packetCapture"), selection: $model.packetFilter) {
          Text(OJDLocalized.string("ui.developer.packetFilterActivity")).tag(
            DeveloperToolsViewModel.PacketFilter.activity
          )
          Text(OJDLocalized.string("ui.developer.packetFilterAll")).tag(
            DeveloperToolsViewModel.PacketFilter.all
          )
        }.pickerStyle(.segmented).labelsHidden()
        HStack(spacing: 8) {
          if model.isCapturing {
            Button(OJDLocalized.string("action.stop"), action: model.stopCapture)
          } else {
            Button(OJDLocalized.string("ui.developer.startCapture"), action: model.startCapture)
              .disabled(model.selectedDevice == nil)
          }
          Button(OJDLocalized.string("action.clear"), action: model.clearCapture)
            .disabled(model.packets.isEmpty && model.observedExtraInputs.isEmpty)
          Spacer(minLength: 12)
          Button(OJDLocalized.string("action.copyAll"), action: model.copyPacketCapture)
            .disabled(model.packets.isEmpty)
          Button(OJDLocalized.string("action.export"), action: model.exportPacketCapture)
            .disabled(model.packets.isEmpty)
        }
        packetList(displayedPackets)
        if model.hiddenIdlePacketCount > 0 {
          Text(
            OJDLocalized.plural("ui.developer.hiddenIdlePackets", model.hiddenIdlePacketCount)
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Text(OJDLocalized.string("ui.developer.packetSharingWarning")).font(.caption)
          .foregroundColor(Color(NSColor.secondaryLabelColor))
      }
    }

    @ViewBuilder
    private var captureStatus: some View {
      switch model.captureState {
      case .idle:
        statusLabel(OJDLocalized.string("ui.developer.ready"), symbol: "circle")
      case .starting:
        statusLabel(
          OJDLocalized.string("ui.developer.starting"),
          symbol: "clock"
        )
      case .capturing:
        statusLabel(
          OJDLocalized.string("ui.developer.capturing"),
          symbol: "record.circle"
        )
      case .stopped:
        statusLabel(
          OJDLocalized.plural(
            "ui.developer.stoppedPackets",
            model.displayedPackets.count
          ),
          symbol: "stop.circle"
        )
      case .noPackets:
        statusLabel(
          OJDLocalized.string("ui.developer.noPackets"),
          symbol: "tray"
        )
      case .failed(let message):
        statusLabel(message, symbol: SemanticState.failure.presentation.symbolName).foregroundColor(
          Color(SemanticState.failure.presentation.tone.color)
        )
      }
    }

    @ViewBuilder
    private func packetList(_ packets: [PacketLogEntry]) -> some View {
      if packets.isEmpty {
        Text(
          model.isCapturing
            ? OJDLocalized.string("ui.developer.waitingForPackets")
            : OJDLocalized.string("ui.developer.emptyCapture")
        ).foregroundColor(Color(NSColor.secondaryLabelColor))
        if model.isCapturing {
          Text(OJDLocalized.string("ui.developer.keepAliveNote")).font(.caption).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
      } else {
        DeveloperPacketTable(packets: packets).frame(minHeight: 160, maxHeight: 240)
      }
    }

    private func statusLabel(_ text: String, symbol: String) -> some View {
      HStack(spacing: 6) {
        OJDSystemSymbol(
          name: symbol,
          fallback: OJDLocalized.string("term.status")
        ).accessibilityHidden(true)
        Text(text)
      }.accessibilityElement(children: .combine)
    }
  }

  private struct DeveloperPacketTable: NSViewRepresentable {
    let packets: [PacketLogEntry]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
      let table = NSTableView()
      table.headerView = NSTableHeaderView()
      table.usesAlternatingRowBackgroundColors = true
      table.rowHeight = 20
      table.delegate = context.coordinator
      table.dataSource = context.coordinator
      table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
      for (identifier, title, width) in [
        ("time", OJDLocalized.string("ui.developer.packetColumnTime"), 80.0),
        ("direction", OJDLocalized.string("ui.developer.packetColumnDirection"), 90.0),
        ("bytes", OJDLocalized.string("ui.developer.packetColumnBytes"), 60.0),
        ("data", OJDLocalized.string("ui.developer.packetColumnData"), 300.0),
      ] {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = width
        table.addTableColumn(column)
      }
      let scrollView = NSScrollView()
      scrollView.documentView = table
      scrollView.hasVerticalScroller = true
      scrollView.hasHorizontalScroller = true
      scrollView.autohidesScrollers = true
      scrollView.borderType = .bezelBorder
      scrollView.setAccessibilityLabel(
        OJDLocalized.string("ui.developer.packetCapture")
      )
      return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      context.coordinator.packets = packets
      (scrollView.documentView as? NSTableView)?.reloadData()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
      var packets: [PacketLogEntry] = []

      func numberOfRows(in tableView: NSTableView) -> Int { packets.count }

      func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
      ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("packet-cell")
        let cell =
          (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView)
          ?? NSTableCellView()
        cell.identifier = identifier
        let textField: NSTextField
        if let existing = cell.textField {
          textField = existing
        } else {
          textField = NSTextField(labelWithString: "")
          textField.translatesAutoresizingMaskIntoConstraints = false
          textField.font = NSFont.monospacedSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
          )
          textField.lineBreakMode = .byClipping
          cell.addSubview(textField)
          cell.textField = textField
          NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
          ])
        }
        let packet = packets[row]
        let firstTimestamp = packets.first?.timestamp ?? packet.timestamp
        switch tableColumn?.identifier.rawValue {
        case "time":
          textField.stringValue = String(format: "+%.3fs", packet.timestamp - firstTimestamp)
        case "direction": textField.stringValue = packet.direction.rawValue.uppercased()
        case "bytes": textField.stringValue = String(packet.length)
        default: textField.stringValue = packet.hex
        }
        return cell
      }
    }
  }

#endif
