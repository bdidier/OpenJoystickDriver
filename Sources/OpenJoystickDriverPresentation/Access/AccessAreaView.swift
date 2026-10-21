#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Access area: what macOS lets the app do, and which programs and web pages may use the
  /// endpoint that `ojd access` manages.
  struct AccessAreaView: View {
    @ObservedObject
    var runtime: RuntimeViewModel
    @ObservedObject
    var model: AccessViewModel
    let restartApplication: @MainActor () -> Void
    @StateObject
    private var notificationPermission: NotificationPermissionModel

    @MainActor
    init(
      runtime: RuntimeViewModel,
      model: AccessViewModel,
      restartApplication: @escaping @MainActor () -> Void
    ) {
      self.runtime = runtime
      self.model = model
      self.restartApplication = restartApplication
      _notificationPermission = StateObject(wrappedValue: NotificationPermissionModel())
    }

    private var readiness: AccessReadiness {
      AccessReadiness(
        permissionState: runtime.permissionState,
        statusState: runtime.statusState,
        notificationState: notificationPermission.state,
        notificationSettings: notificationPermission.settings
      )
    }

    var body: some View {
      GeometryReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            PageHeader(
              title: OJDLocalized.string("access.title"),
              subtitle: OJDLocalized.string("access.subtitle")
            )
            if let failure = model.failure {
              errorView(failure, actionTitle: "access.dismiss", action: model.dismissFailure)
            }
            accessSummary(width: proxy.size.width - 56)
            endpointContent
          }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
      }.onAppear { notificationPermission.refresh() }.onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in notificationPermission.refresh() }.task { await model.refresh() }.sheet(
        item: $model.sheet
      ) { sheet in
        switch sheet {
        case .confirm(let pending):
          AccessConfirmationSheet(model: model, pending: pending)
        case .tokenForm:
          AccessTokenFormSheet(model: model)
        case .issuedToken(let issued):
          AccessIssuedTokenSheet(issued: issued) { model.closeIssuedToken() }
        }
      }
    }

    private func errorView(
      _ failure: AccessFailure,
      actionTitle: String,
      action: @escaping () -> Void
    ) -> some View {
      InlineErrorView(
        message: failure.message,
        code: failure.code,
        detailsTitle: OJDLocalized.string("access.details"),
        detailsAccessibilityLabel: OJDLocalized.string("a11y.access.details"),
        actionTitle: OJDLocalized.string(actionTitle),
        actionAccessibilityLabel: OJDLocalized.string(
          actionTitle == "access.dismiss" ? "a11y.access.dismissError" : "a11y.access.tryAgain"
        ),
        action: action
      )
    }

    // MARK: macOS permissions

    private func accessSummary(width: CGFloat) -> some View {
      let readiness = readiness
      return GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          accessCards(width: width, readiness: readiness)
          if readiness.needsRestart {
            Button(
              OJDLocalized.string("permissions.restartApplication"),
              action: restartApplication
            ).ojdAccessibilityLabel(OJDLocalized.string("a11y.access.restart"))
          }
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("settings.accessReadiness")).font(.headline)
      }.ojdAccessibilityLabel(OJDLocalized.string("settings.accessReadinessAccessibility"))
        .ojdAccessibilityValue(readiness.summaryValue)
    }

    @ViewBuilder
    private func accessCards(width: CGFloat, readiness: AccessReadiness) -> some View {
      let cards = [
        inputReadCard(readiness.inputRead), inputInjectCard(readiness.inputInject),
        postEventCard(readiness.postEvent), notificationCard(readiness.notification),
      ]
      if width >= 850 {
        HStack(alignment: .top, spacing: 12) {
          cards[0]; cards[1]; cards[2]; cards[3]
        }
      } else if width >= 430 {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .top, spacing: 12) {
            cards[0]; cards[1]
          }
          HStack(alignment: .top, spacing: 12) {
            cards[2]; cards[3]
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 12) {
          cards[0]; cards[1]; cards[2]; cards[3]
        }
      }
    }

    private func inputReadCard(_ status: AccessReadinessStatus) -> AccessRequirementCard {
      AccessRequirementCard(
        title: OJDLocalized.string("common.inputRead"),
        value: status.value,
        symbol: "keyboard",
        tone: status.tone,
        action: status.isActionable
          ? {
            PermissionAccessActions.requestControllerAccess(
              viewModel: runtime,
              requirement: .inputRead
            )
          } : nil
      )
    }

    private func inputInjectCard(_ status: AccessReadinessStatus) -> AccessRequirementCard {
      AccessRequirementCard(
        title: OJDLocalized.string("common.inputInject"),
        value: status.value,
        symbol: "lock.shield",
        tone: status.tone,
        action: status.isActionable
          ? {
            PermissionAccessActions.requestControllerAccess(
              viewModel: runtime,
              requirement: .inputInject
            )
          } : nil
      )
    }

    private func postEventCard(_ status: AccessReadinessStatus) -> AccessRequirementCard {
      AccessRequirementCard(
        title: OJDLocalized.string("common.keyboardPointer"),
        value: status.value,
        symbol: "cursorarrow",
        tone: status.tone,
        action: status.isActionable
          ? { PermissionAccessActions.requestPostEventAccess(viewModel: runtime) } : nil
      )
    }

    private func notificationCard(_ status: AccessReadinessStatus) -> AccessRequirementCard {
      AccessRequirementCard(
        title: OJDLocalized.string("settings.notifications"),
        value: status.value,
        symbol: "bell",
        tone: status.tone,
        action: status.isActionable ? { notificationPermission.requestOrOpenSettings() } : nil
      )
    }

    // MARK: Endpoint

    @ViewBuilder
    private var endpointContent: some View {
      switch model.load {
      case .loading: LoadingStateView(message: OJDLocalized.string("access.loading"))
      case .failed(let failure):
        errorView(failure, actionTitle: "access.tryAgain") { Task { await model.refresh() } }
      case .loaded(let status):
        endpointSection(status)
        webSection(status.web)
        grantsSection(status)
        tokensSection(status)
        refusedSection(status)
        connectionsSection(status)
      }
    }

    private func sectionTitle(_ key: String) -> some View {
      Text(OJDLocalized.string(key)).font(.title2.weight(.semibold))
        .accessibilityAddTraits(.isHeader)
    }

    private func endpointSection(_ status: AccessStatusPayload) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        sectionTitle("access.endpoint")
        GroupBox {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
              Text(OJDLocalized.string(status.enabled ? "access.on" : "access.off"))
                .font(.body.weight(.medium))
              Text(OJDLocalized.formatted("access.socket", status.socketPath)).font(.caption)
                .foregroundColor(Color(NSColor.secondaryLabelColor)).textSelection(.enabled)
            }
            Spacer()
            if status.enabled {
              Button(OJDLocalized.string("access.disable")) {
                Task { await model.disableEndpoint() }
              }.disabled(model.busy).ojdAccessibilityLabel(
                OJDLocalized.string("a11y.access.disableEndpoint")
              )
            } else {
              Button(OJDLocalized.string("access.enable")) { model.requestEnableEndpoint() }
                .disabled(model.busy).ojdAccessibilityLabel(
                  OJDLocalized.string("a11y.access.enableEndpoint")
                )
            }
          }.padding(4)
        }
      }
    }

    private func webSection(_ web: AccessWebStatus) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        sectionTitle("access.web")
        GroupBox {
          VStack(alignment: .leading, spacing: 8) {
            Text(AccessPresentation.web(web)).textSelection(.enabled)
            if web.enabled {
              Text(OJDLocalized.formatted("access.web.pages", web.pagesPath)).font(.caption)
                .foregroundColor(Color(NSColor.secondaryLabelColor)).textSelection(.enabled)
              Button(OJDLocalized.string("access.disable")) {
                Task { await model.disableWeb() }
              }.disabled(model.busy).ojdAccessibilityLabel(
                OJDLocalized.string("a11y.access.disableWeb")
              )
            } else {
              HStack {
                TextField(OJDLocalized.string("access.web.port"), text: $model.portText)
                  .frame(width: 120).ojdAccessibilityLabel(
                    OJDLocalized.string("a11y.access.webPort")
                  )
                Button(OJDLocalized.string("access.enable")) { model.requestEnableWeb() }
                  .disabled(model.busy).ojdAccessibilityLabel(
                    OJDLocalized.string("a11y.access.enableWeb")
                  )
              }
            }
          }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }

    private func grantsSection(_ status: AccessStatusPayload) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          sectionTitle("access.grants")
          Spacer()
          Button(OJDLocalized.string("access.grantProgram")) {
            if let url = AccessFilePicker.chooseProgram() { model.requestGrant(programAt: url) }
          }.disabled(model.busy).ojdAccessibilityLabel(
            OJDLocalized.string("a11y.access.grantProgram")
          )
        }
        if status.grants.isEmpty {
          Text(OJDLocalized.string("access.none")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
        ForEach(status.grants, id: \.id) { grant in
          row(
            title: grant.identifier,
            detail: OJDLocalized.formatted(
              "access.detail.pair",
              AccessPresentation.signer(grant.publisher.kind, grant.publisher.id),
              AccessPresentation.scopes(grant.scopes)
            ),
            path: grant.path,
            actionTitle: OJDLocalized.string("access.revoke"),
            actionLabel: OJDLocalized.formatted("a11y.access.revokeGrant", grant.identifier)
          ) { model.requestRevoke(grant) }
        }
      }
    }

    private func tokensSection(_ status: AccessStatusPayload) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          sectionTitle("access.tokens")
          Spacer()
          Button(OJDLocalized.string("access.grantToken")) { model.requestTokenForm() }
            .disabled(model.busy).ojdAccessibilityLabel(
              OJDLocalized.string("a11y.access.grantToken")
            )
        }
        if status.tokens.isEmpty {
          Text(OJDLocalized.string("access.none")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
        ForEach(status.tokens, id: \.id) { token in
          row(
            title: token.name,
            detail: AccessPresentation.scopes(token.scopes),
            path: token.origins.joined(separator: ", "),
            actionTitle: OJDLocalized.string("access.revoke"),
            actionLabel: OJDLocalized.formatted("a11y.access.revokeToken", token.name)
          ) { model.requestRevoke(token) }
        }
      }
    }

    private func refusedSection(_ status: AccessStatusPayload) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        sectionTitle("access.refused")
        Text(OJDLocalized.string("access.refused.message")).font(.caption).foregroundColor(
          Color(NSColor.secondaryLabelColor)
        )
        if status.refused.isEmpty && status.refusedTokens.isEmpty {
          Text(OJDLocalized.string("access.none")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
        ForEach(status.refused, id: \.id) { client in
          row(
            title: client.identifier,
            detail: OJDLocalized.formatted(
              "access.detail.triple",
              AccessPresentation.signer(client.publisher.kind, client.publisher.id),
              AccessPresentation.scopes(client.scopes),
              client.reason
            ),
            path: client.path,
            actionTitle: OJDLocalized.string("access.grant"),
            actionLabel: OJDLocalized.formatted("a11y.access.grantRefused", client.identifier)
          ) { model.requestRefusedGrant(client) }
        }
        ForEach(Array(status.refusedTokens.enumerated()), id: \.offset) { _, token in
          row(
            title: token.name.map { OJDLocalized.formatted("access.token.named", $0) }
              ?? OJDLocalized.string("access.token.unknown"),
            detail: OJDLocalized.formatted(
              "access.detail.triple",
              AccessPresentation.transport(token.transport),
              AccessPresentation.scopes(token.scopes),
              token.reason
            ),
            path: token.origin,
            actionTitle: nil,
            actionLabel: ""
          ) {}
        }
      }
    }

    private func connectionsSection(_ status: AccessStatusPayload) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        sectionTitle("access.connections")
        if status.connections.isEmpty {
          Text(OJDLocalized.string("access.none")).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
        ForEach(status.connections, id: \.id) { connection in
          row(
            title: connection.identifier,
            detail: OJDLocalized.formatted(
              "access.detail.pair",
              AccessPresentation.transport(connection.transport),
              AccessPresentation.scopes(connection.scopes)
            ),
            path: nil,
            actionTitle: nil,
            actionLabel: ""
          ) {}
        }
      }
    }

    private func row(
      title: String,
      detail: String,
      path: String?,
      actionTitle: String?,
      actionLabel: String,
      action: @escaping () -> Void
    ) -> some View {
      GroupBox {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.medium))
            Text(detail).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
            if let path {
              Text(path).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
            }
          }.textSelection(.enabled)
          Spacer()
          if let actionTitle {
            Button(actionTitle, action: action).disabled(model.busy)
              .ojdAccessibilityLabel(actionLabel)
          }
        }.padding(4)
      }.ojdAccessibilityLabel(title).ojdAccessibilityValue(detail)
    }
  }

#endif
