import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draftBaseURL = ""

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "switch.2")
                }

            displayTab
                .tabItem {
                    Label("Display", systemImage: "menubar.rectangle")
                }

            alertsTab
                .tabItem {
                    Label("Alerts", systemImage: "bell.badge")
                }

            adminTab
                .tabItem {
                    Label("Admin", systemImage: "gearshape.2")
                }
        }
        .frame(width: 520, height: 620)
        .task {
            draftBaseURL = model.baseURL
            await model.startIfNeeded()
        }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsHeader(
                    title: "Status Hub",
                    detail: "Connect the app to your Ubuntu hub and choose which device you are monitoring."
                )
                connectionSection
                authSection
                if !model.devices.isEmpty {
                    deviceSection
                }
                footerError
            }
            .padding(20)
        }
    }

    private var displayTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsHeader(
                    title: "Display",
                    detail: "Shape what appears directly in the menu bar and how the dropdown feels."
                )
                appearanceSection
                pinnedStatsSection
                if !model.widgets.isEmpty {
                    layoutSection
                }
                footerError
            }
            .padding(20)
        }
    }

    private var alertsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsHeader(
                    title: "Alerts",
                    detail: "Review rules and recent events for the selected Ubuntu machine."
                )
                if !model.devices.isEmpty {
                    alertRulesSection
                    recentEventsSection
                }
                footerError
            }
            .padding(20)
        }
    }

    private var adminTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsHeader(
                    title: "Admin",
                    detail: "Manage notification channels and client tokens used by the menu bar app."
                )
                adminSection
                if model.hasAdminSession {
                    notificationChannelsSection
                    clientTokensSection
                }
                footerError
            }
            .padding(20)
        }
    }

    private func settingsHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionSection: some View {
        SettingsCard("Connection") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Hub URL", text: $draftBaseURL)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        StatusPill(label: model.connectionLabel, tint: connectionTint)
                        if model.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Spacer()
                        Button("Apply Hub URL") {
                            Task { await model.applyBaseURL(draftBaseURL) }
                        }
                    }

                    Text(model.statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var authSection: some View {
        SettingsCard("Access") {
            VStack(alignment: .leading, spacing: 12) {
                SecureField("Admin password", text: $model.passwordInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(model.isAuthenticating ? "Connecting..." : "Create secure client token") {
                        Task { await model.signInAndCreateClientToken() }
                    }
                    .disabled(model.isAuthenticating || draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Forget token") {
                        model.signOut()
                    }
                    .disabled(!model.isSignedIn)
                }

                Text(model.hasAdminSession ? "Admin tools are unlocked for this app session." : "Enter the admin password when you need to create a token or unlock admin tools.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deviceSection: some View {
        SettingsCard("Device") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Selected device", selection: Binding(
                    get: { model.selectedDeviceID },
                    set: { model.selectDevice($0) }
                )) {
                    ForEach(model.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }

                HStack {
                    Button("Refresh now") { model.refresh() }
                    Button("Reconnect stream") { model.manualReconnect() }
                }
            }
        }
    }

    private var appearanceSection: some View {
        SettingsCard("Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Accent style", selection: $model.menuAccentStyle) {
                    Text("Automatic").tag("system")
                    Text("Blue").tag("blue")
                    Text("Green").tag("green")
                    Text("Orange").tag("orange")
                    Text("Red").tag("red")
                }

                Text("Pinned stats use this accent in the menu bar label and dropdown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pinnedStatsSection: some View {
        SettingsCard("Pinned Top Bar Stats") {
            VStack(alignment: .leading, spacing: 12) {
                if model.pinnedWidgets.isEmpty {
                    Text("No pinned stats yet. Pin widgets below to show them directly in the top bar beside the main icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.pinnedWidgets.enumerated()), id: \.element.id) { index, widget in
                        HStack {
                            PinnedStatChip(
                                label: model.compactLabel(for: widget),
                                value: model.compactValue(for: widget),
                                tint: model.menuAccentColor
                            )
                            Spacer()
                            Button("Up") { model.movePinnedWidget(at: index, by: -1) }
                                .disabled(index == 0)
                            Button("Down") { model.movePinnedWidget(at: index, by: 1) }
                                .disabled(index == model.pinnedWidgets.count - 1)
                            Button("Unpin") { model.togglePinnedWidget(widget.id) }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Available widgets")
                        .font(.headline)

                    ForEach(model.widgets.filter(\.visible)) { widget in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(widget.title)
                                    .font(.body.weight(.medium))
                                Text(model.widgetSummary(for: widget).value)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(model.isWidgetPinned(widget.id) ? "Pinned" : "Pin to top bar") {
                                model.togglePinnedWidget(widget.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var layoutSection: some View {
        SettingsCard("Dropdown Layout") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(model.widgets.enumerated()), id: \.element.id) { index, widget in
                    HStack(spacing: 12) {
                        Toggle(widget.title, isOn: Binding(
                            get: { model.widgets[index].visible },
                            set: { model.widgets[index].visible = $0 }
                        ))
                        Spacer()
                        Button("Up") { model.moveWidget(at: index, by: -1) }
                            .disabled(index == 0)
                        Button("Down") { model.moveWidget(at: index, by: 1) }
                            .disabled(index == model.widgets.count - 1)
                    }
                }

                HStack {
                    Button(model.isSavingLayout ? "Saving..." : "Save dropdown layout") {
                        Task { await model.saveLayout() }
                    }
                    .disabled(model.isSavingLayout)

                    if model.isSavingLayout {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var alertRulesSection: some View {
        SettingsCard("Alert Rules") {
            VStack(alignment: .leading, spacing: 12) {
                if model.alertRules.isEmpty {
                    Text("No alert rules for this device yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.alertRules.enumerated()), id: \.element.id) { index, rule in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Toggle(rule.title, isOn: Binding(
                                    get: { model.alertRules[index].enabled },
                                    set: { model.alertRules[index].enabled = $0 }
                                ))
                                Spacer()
                                Text(rule.metric.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Threshold")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "Threshold",
                                    value: Binding(
                                        get: { model.alertRules[index].threshold },
                                        set: { model.alertRules[index].threshold = $0 }
                                    ),
                                    format: .number
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)

                                Text("Severity")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Severity", selection: Binding(
                                    get: { model.alertRules[index].severity },
                                    set: { model.alertRules[index].severity = $0 }
                                )) {
                                    Text("Info").tag("info")
                                    Text("Warning").tag("warning")
                                    Text("Critical").tag("critical")
                                }
                                .frame(width: 110)
                            }

                            if !model.notificationChannels.isEmpty {
                                Menu {
                                    ForEach(model.notificationChannels) { channel in
                                        Button {
                                            model.toggleChannel(channel.id, on: rule.id)
                                        } label: {
                                            Label(channel.name, systemImage: rule.channels.contains(channel.id) ? "checkmark.circle.fill" : "circle")
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text("Channels")
                                        Spacer()
                                        Text(model.channelNames(for: rule))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .menuStyle(.borderlessButton)
                            }
                        }
                        if index != model.alertRules.count - 1 {
                            Divider()
                        }
                    }
                }

                Button(model.isSavingAlerts ? "Saving..." : "Save alert rules") {
                    Task { await model.saveAlertRules() }
                }
                .disabled(model.isSavingAlerts || model.alertRules.isEmpty)
            }
        }
    }

    private var recentEventsSection: some View {
        SettingsCard("Recent Events") {
            VStack(alignment: .leading, spacing: 10) {
                if model.events.isEmpty {
                    Text("No recent events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.events.prefix(8)) { event in
                        EventRow(
                            event: event,
                            canAcknowledge: event.acknowledgedAt == nil,
                            isWorking: model.isAcknowledgingEvent == event.id
                        ) {
                            Task { await model.acknowledgeEvent(event.id) }
                        }
                    }
                }
            }
        }
    }

    private var adminSection: some View {
        SettingsCard("Admin Tools") {
            VStack(alignment: .leading, spacing: 12) {
                if model.hasAdminSession {
                    HStack {
                        StatusPill(label: "Unlocked", tint: .green)
                        if model.isLoadingAdminData {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Spacer()
                        Button("Refresh admin data") {
                            Task { await model.refreshAdminData() }
                        }
                    }
                } else {
                    Button(model.isAuthenticating ? "Unlocking..." : "Unlock admin tools") {
                        Task { await model.unlockAdminTools() }
                    }
                    .disabled(model.isAuthenticating || model.passwordInput.isEmpty)
                }

                Text("Use admin tools to manage notification channels and client tokens without leaving the Mac app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var notificationChannelsSection: some View {
        SettingsCard("Notification Channels") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(model.notificationChannels.enumerated()), id: \.element.id) { index, channel in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle(channel.name, isOn: Binding(
                                get: { model.notificationChannels[index].enabled },
                                set: { model.notificationChannels[index].enabled = $0 }
                            ))
                            Spacer()
                            Button("Remove") {
                                model.removeNotificationChannel(channel.id)
                            }
                        }

                        TextField("Channel name", text: Binding(
                            get: { model.notificationChannels[index].name },
                            set: { model.notificationChannels[index].name = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        TextField("Server URL", text: Binding(
                            get: { model.notificationChannels[index].serverURL },
                            set: { model.notificationChannels[index].serverURL = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        TextField("Topic", text: Binding(
                            get: { model.notificationChannels[index].topic },
                            set: { model.notificationChannels[index].topic = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    if index != model.notificationChannels.count - 1 {
                        Divider()
                    }
                }

                HStack {
                    Button("Add ntfy channel") {
                        model.addNotificationChannel()
                    }
                    Button(model.isSavingChannels ? "Saving..." : "Save channels") {
                        Task { await model.saveNotificationChannels() }
                    }
                    .disabled(model.isSavingChannels)
                }
            }
        }
    }

    private var clientTokensSection: some View {
        SettingsCard("Client Tokens") {
            VStack(alignment: .leading, spacing: 10) {
                if model.clientTokens.isEmpty {
                    Text("No client tokens found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.clientTokens) { token in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(token.name)
                                    .font(.callout.weight(.semibold))
                                Text("\(token.kind) · created \(formatTimestamp(token.createdAt))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Last used: \(formatTimestamp(token.lastUsedAt))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if token.revoked {
                                StatusPill(label: "Revoked", tint: .red)
                            } else {
                                Button(model.revokingTokenID == token.id ? "Revoking..." : "Revoke") {
                                    Task { await model.revokeClientToken(token.id) }
                                }
                                .disabled(model.revokingTokenID == token.id)
                            }
                        }
                        if token.id != model.clientTokens.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var footerError: some View {
        Group {
            if !model.errorMessage.isEmpty {
                Text(model.errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var connectionTint: Color {
        switch model.connectionState {
        case .ready:
            return .green
        case .loading:
            return .blue
        case .degraded:
            return .orange
        case .error, .signedOut:
            return .red
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerPanel

            if model.isSignedIn {
                if model.devices.count > 1 {
                    deviceSection
                }
                highlightSection
                widgetSection
                alertSection
                controlsSection
            } else {
                signedOutSection
            }
        }
        .padding(14)
        .frame(width: 360)
        .task {
            await model.startIfNeeded()
        }
    }

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.currentDevice?.name ?? "Status Hub")
                        .font(.headline)
                    Text(model.statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(label: model.connectionLabel, tint: headerTint)
                    Text(model.alertSummary.highestLevel.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Device")
            Picker("Device", selection: Binding(
                get: { model.selectedDeviceID },
                set: { model.selectDevice($0) }
            )) {
                ForEach(model.devices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .labelsHidden()
        }
    }

    private var highlightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Highlights")
            HStack(spacing: 8) {
                ForEach(model.pinnedWidgets.prefix(3)) { widget in
                    PinnedStatChip(
                        label: model.compactLabel(for: widget),
                        value: model.compactValue(for: widget),
                        tint: model.menuAccentColor
                    )
                }
            }
        }
    }

    private var widgetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Live Details")
            if model.widgets.filter(\.visible).isEmpty {
                EmptyStateRow(
                    symbol: "slider.horizontal.3",
                    title: "No visible widgets",
                    detail: "Open Settings to restore items."
                )
            } else {
                ForEach(model.widgets.filter(\.visible).sorted(by: { $0.order < $1.order })) { widget in
                    let summary = model.widgetSummary(for: widget)
                    MetricRow(
                        title: widget.title,
                        value: summary.value,
                        detail: summary.detail,
                        symbol: summary.symbol
                    )
                }
            }
        }
    }

    private var alertSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Recent Alerts")
            if model.events.isEmpty {
                EmptyStateRow(
                    symbol: "bell.slash",
                    title: "No recent alerts",
                    detail: "New events will appear here."
                )
            } else {
                ForEach(model.events.prefix(4)) { event in
                    EventRow(
                        event: event,
                        canAcknowledge: event.acknowledgedAt == nil,
                        isWorking: model.isAcknowledgingEvent == event.id
                    ) {
                        Task { await model.acknowledgeEvent(event.id) }
                    }
                }
            }
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Controls")
            HStack {
                Button("Refresh") { model.refresh() }
                    .disabled(model.isRefreshing)
                Button("Reconnect") { model.manualReconnect() }
            }

            HStack {
                SettingsLink {
                    Text("Open Settings")
                }
                Button("Sign Out") { model.signOut() }
            }
        }
    }

    private var signedOutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EmptyStateRow(
                symbol: "lock.circle",
                title: "Not connected",
                detail: "Open Settings, enter the hub URL, and create a secure client token."
            )
            SettingsLink {
                Text("Open Settings")
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }

    private var headerTint: Color {
        switch model.connectionState {
        case .ready:
            return .green
        case .loading:
            return .blue
        case .degraded:
            return .orange
        case .error, .signedOut:
            return .red
        }
    }
}

struct MenuBarLabelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: model.iconName)
                .foregroundStyle(model.menuAccentColor)
            ForEach(model.pinnedWidgets.prefix(3)) { widget in
                PinnedStatChip(
                    label: model.compactLabel(for: widget),
                    value: model.compactValue(for: widget),
                    tint: model.menuAccentColor
                )
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PinnedStatChip: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    let detail: String?
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 18)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(value)
                    .font(.callout.weight(.medium))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }
}

struct EventRow: View {
    let event: EventSummary
    var canAcknowledge = false
    var isWorking = false
    var acknowledge: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconTint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                Text(event.body)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formatTimestamp(event.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if event.acknowledgedAt != nil {
                    Text("Acknowledged")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if canAcknowledge, let acknowledge {
                    Button(isWorking ? "Saving..." : "Acknowledge") {
                        acknowledge()
                    }
                    .buttonStyle(.link)
                    .disabled(isWorking)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(iconTint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var iconName: String {
        switch event.severity {
        case "critical":
            return "exclamationmark.triangle.fill"
        case "warning":
            return "exclamationmark.circle.fill"
        default:
            return "info.circle.fill"
        }
    }

    private var iconTint: Color {
        switch event.severity {
        case "critical":
            return .red
        case "warning":
            return .orange
        default:
            return .blue
        }
    }
}

struct EmptyStateRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

struct StatusPill: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}
