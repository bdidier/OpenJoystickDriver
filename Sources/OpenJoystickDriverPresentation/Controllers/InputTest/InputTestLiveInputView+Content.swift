#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension InputTestLiveInputView {
    var body: some View { content }

    var content: some View {
      let snapshot = liveState.snapshot
      let pressed = snapshot.pressed
      let symbols = InputTestControllerSymbolSet.resolve(for: presentation.glyphFamily)
      return VStack(spacing: 10) {
        shoulderRow(snapshot: snapshot, symbols: symbols)
        Divider()
        HStack(alignment: .center, spacing: 18) {
          dpadCluster(hat: snapshot.hat).frame(maxWidth: .infinity)
          systemCluster(pressed: pressed, symbols: symbols).frame(
            maxWidth: .infinity
          )
          faceButtonCluster(pressed: pressed, symbols: symbols).frame(maxWidth: .infinity)
        }
        Divider()
        HStack(alignment: .top, spacing: 24) {
          InputTestStickView(
            title: OJDLocalized.string("inputTest.leftStick"),
            x: snapshot.leftStick.x.normalized,
            y: snapshot.leftStick.y.normalized,
            clickPresentation: symbols.leftStickClick,
            clickActive: pressed.contains(.leftStickClick)
          )
          InputTestStickView(
            title: OJDLocalized.string("inputTest.rightStick"),
            x: snapshot.rightStick.x.normalized,
            y: snapshot.rightStick.y.normalized,
            clickPresentation: symbols.rightStickClick,
            clickActive: pressed.contains(.rightStickClick)
          )
        }
        let additionalButtons = InputTestButtonPresentation.additionalControls(in: snapshot)
        if !additionalButtons.isEmpty {
          Divider()
          VStack(alignment: .leading, spacing: 8) {
            Text(OJDLocalized.string("inputTest.additionalButtons"))
              .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
              ForEach(additionalButtons, id: \.self) { control in
                InputTestIndicator(
                  title: InputTestButtonPresentation.localizedTitle(for: control),
                  active: true
                )
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      }.padding(6)
    }

    private func shoulderRow(
      snapshot: ControllerState,
      symbols: InputTestControllerSymbolSet
    ) -> some View {
      HStack(spacing: 10) {
        indicator(symbols.leftShoulder, active: snapshot.pressed.contains(.leftShoulder))
        indicator(
          symbols.leftTrigger,
          value: snapshot.leftTrigger.normalized,
          active: snapshot.leftTrigger.normalized > 0.05
            || snapshot.pressed.contains(.leftTrigger)
        )
        indicator(
          symbols.rightTrigger,
          value: snapshot.rightTrigger.normalized,
          active: snapshot.rightTrigger.normalized > 0.05
            || snapshot.pressed.contains(.rightTrigger)
        )
        indicator(symbols.rightShoulder, active: snapshot.pressed.contains(.rightShoulder))
      }
    }

    private func dpadCluster(hat: HatDirection) -> some View {
      let directions = RuntimePresentation.dpadDirections(hat)
      return VStack(spacing: 6) {
        dpadIndicator(.up, title: "inputTest.dpadUp", active: directions.contains(.up))
        HStack(spacing: 6) {
          dpadIndicator(.left, title: "inputTest.dpadLeft", active: directions.contains(.left))
          dpadIndicator(.right, title: "inputTest.dpadRight", active: directions.contains(.right))
        }
        dpadIndicator(.down, title: "inputTest.dpadDown", active: directions.contains(.down))
      }
    }

    private func dpadIndicator(
      _ direction: RemappingDpadDirection,
      title: String,
      active: Bool
    ) -> some View {
      indicator(
        OJDLocalized.string(title),
        symbol: InputTestButtonPresentation.dpadSymbol(direction),
        active: active
      )
    }

    @ViewBuilder
    private func systemCluster(
      pressed: Set<Control>,
      symbols: InputTestControllerSymbolSet
    ) -> some View {
      HStack(spacing: 6) {
        indicator(
          symbols.view,
          active: pressed.contains(.back)
        )
        indicator(symbols.guide, active: pressed.contains(.guide))
        indicator(symbols.menu, active: pressed.contains(.start))
      }
    }

    private func faceButtonCluster(
      pressed: Set<Control>,
      symbols: InputTestControllerSymbolSet
    ) -> some View {
      VStack(spacing: 6) {
        indicator(symbols.northFace, active: pressed.contains(.north))
        HStack(spacing: 6) {
          indicator(symbols.westFace, active: pressed.contains(.west))
          indicator(symbols.eastFace, active: pressed.contains(.east))
        }
        indicator(symbols.southFace, active: pressed.contains(.south))
      }
    }

    func indicator(_ title: String, symbol: String, active: Bool) -> some View {
      InputTestIndicator(title: title, symbol: symbol, active: active)
    }

    func indicator(
      _ presentation: InputTestControllerSymbolSet.Control,
      value: Float? = nil,
      active: Bool
    ) -> some View {
      InputTestIndicator(
        title: presentation.title,
        displayedText: value.map { OJDLocalized.formatted("inputTest.axisValue", $0) },
        symbol: presentation.symbol,
        fallbackSymbol: presentation.fallbackSymbol,
        fallbackText: presentation.fallbackText,
        active: active
      )
    }
  }

#endif
