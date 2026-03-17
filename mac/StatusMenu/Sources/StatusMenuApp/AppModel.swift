import Foundation
import Security
import SwiftUI

enum KeychainStore {
    static func saveToken(_ value: String, service: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "status-hub-client-token",
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func loadToken(service: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "status-hub-client-token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    static func deleteToken(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "status-hub-client-token",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @AppStorage("baseURL") var baseURL = "http://localhost:8080"
    @AppStorage("selectedDeviceID") var selectedDeviceID = ""
    @AppStorage("pinnedWidgetIDsByScopeData") private var pinnedWidgetIDsByScopeData = "{}"
    @AppStorage("menuAccentStyle") var menuAccentStyle = "system"

    @Published var passwordInput = ""
    @Published var devices: [DeviceSummary] = []
    @Published var widgets: [WidgetItem] = []
    @Published var events: [EventSummary] = []
    @Published var alertRules: [AlertRuleItem] = []
    @Published var notificationChannels: [NotificationChannelItem] = []
    @Published var clientTokens: [ClientTokenItem] = []
    @Published var alertSummary = AlertSummary(activeCount: 0, highestLevel: "healthy", latestMessage: nil)
    @Published var errorMessage = ""
    @Published var connectionState: ConnectionState = .signedOut
    @Published var isAuthenticating = false
    @Published var isRefreshing = false
    @Published var isSavingLayout = false
    @Published var isSavingAlerts = false
    @Published var isSavingChannels = false
    @Published var isLoadingAdminData = false
    @Published var isAcknowledgingEvent = ""
    @Published var revokingTokenID = ""
    @Published var streamConnected = false

    private let session = URLSession.shared
    private let target = "mac_menu_bar"
    private var adminSessionToken = ""

    private var streamTask: URLSessionWebSocketTask?
    private var listenTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var scheduledBootstrapTask: Task<Void, Never>?
    private var hasStarted = false
    private var bootstrapInFlight = false
    private var bootstrapQueued = false
    private var queuedRefreshMetadata = false
    private var reconnectAttempts = 0
    private var currentStreamURL: URL?

    var currentDevice: DeviceSummary? {
        devices.first(where: { $0.id == selectedDeviceID }) ?? devices.first
    }

    var hasStoredToken: Bool {
        !storedClientToken().isEmpty
    }

    var isSignedIn: Bool {
        hasStoredToken
    }

    var hasAdminSession: Bool {
        !adminSessionToken.isEmpty
    }

    var pinnedWidgetIDs: [String] {
        get {
            guard let data = pinnedWidgetIDsByScopeData.data(using: .utf8),
                  let scoped = try? JSONDecoder().decode([String: [String]].self, from: data) else {
                return []
            }
            return scoped[pinnedScopeKey] ?? []
        }
        set {
            let data = pinnedWidgetIDsByScopeData.data(using: .utf8) ?? Data("{}".utf8)
            var scoped = (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
            scoped[pinnedScopeKey] = newValue
            let encoded = (try? JSONEncoder().encode(scoped)) ?? Data("{}".utf8)
            pinnedWidgetIDsByScopeData = String(data: encoded, encoding: .utf8) ?? "{}"
        }
    }

    var pinnedWidgets: [WidgetItem] {
        let visibleWidgets = widgets.filter(\.visible)
        let visibleByID = Dictionary(uniqueKeysWithValues: visibleWidgets.map { ($0.id, $0) })
        let ordered = pinnedWidgetIDs.compactMap { visibleByID[$0] }
        return ordered.filter { widget in
            ["battery", "cpu-memory", "temperature", "docker", "network", "storage", "overview"].contains(widget.kind)
        }
    }

    var menuAccentColor: Color {
        switch menuAccentStyle {
        case "blue":
            return .blue
        case "green":
            return .green
        case "orange":
            return .orange
        case "red":
            return .red
        default:
            switch alertSummary.highestLevel {
            case "critical":
                return .red
            case "warning":
                return .orange
            default:
                return .primary
            }
        }
    }

    var iconName: String {
        if !hasStoredToken {
            return "lock.circle"
        }
        switch alertSummary.highestLevel {
        case "critical":
            return "exclamationmark.triangle.fill"
        case "warning":
            return "exclamationmark.circle.fill"
        default:
            if connectionState == .error || connectionState == .degraded {
                return "wifi.exclamationmark"
            }
            return currentDevice?.online == false ? "bolt.horizontal.circle.fill" : "server.rack"
        }
    }

    var connectionLabel: String {
        switch connectionState {
        case .signedOut:
            return "Signed out"
        case .loading:
            return "Loading"
        case .ready:
            return streamConnected ? "Live" : "Connected"
        case .degraded:
            return "Degraded"
        case .error:
            return "Error"
        }
    }

    var statusDetail: String {
        if let message = alertSummary.latestMessage, !message.isEmpty {
            return message
        }
        if let device = currentDevice {
            return device.online ? "Receiving status from \(device.name)" : "\(device.name) is offline or stale"
        }
        if hasStoredToken {
            return "Waiting for a device to appear"
        }
        return "Connect the menu bar app to your hub"
    }

    func storedClientToken() -> String {
        KeychainStore.loadToken(service: baseURL)
    }

    func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true
        if hasStoredToken {
            await bootstrap(refreshMetadata: true)
        } else {
            connectionState = .signedOut
        }
    }

    func applyBaseURL(_ value: String) async {
        let sanitized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            errorMessage = "Hub URL is required"
            connectionState = .error
            return
        }
        baseURL = sanitized
        selectedDeviceID = ""
        disconnectStream()
        devices = []
        widgets = []
        events = []
        alertRules = []
        notificationChannels = []
        clientTokens = []
        alertSummary = AlertSummary(activeCount: 0, highestLevel: "healthy", latestMessage: nil)
        errorMessage = ""
        adminSessionToken = ""
        hasStarted = true
        if hasStoredToken {
            await bootstrap(forceReconnect: true, refreshMetadata: true)
        } else {
            connectionState = .signedOut
        }
    }

    func signOut() {
        KeychainStore.deleteToken(service: baseURL)
        passwordInput = ""
        selectedDeviceID = ""
        devices = []
        widgets = []
        events = []
        alertRules = []
        notificationChannels = []
        clientTokens = []
        alertSummary = AlertSummary(activeCount: 0, highestLevel: "healthy", latestMessage: nil)
        errorMessage = ""
        connectionState = .signedOut
        adminSessionToken = ""
        disconnectStream()
    }

    func selectDevice(_ deviceID: String) {
        guard selectedDeviceID != deviceID else { return }
        selectedDeviceID = deviceID
        scheduleBootstrap(immediate: true, refreshMetadata: true)
    }

    func manualReconnect() {
        disconnectStream()
        scheduleBootstrap(immediate: true, forceReconnect: true, refreshMetadata: true)
    }

    func refresh() {
        scheduleBootstrap(immediate: true, refreshMetadata: true)
    }

    func bootstrap(forceReconnect: Bool = false, refreshMetadata: Bool = false) async {
        if bootstrapInFlight {
            bootstrapQueued = true
            queuedRefreshMetadata = queuedRefreshMetadata || refreshMetadata
            return
        }
        let token = storedClientToken()
        guard !token.isEmpty else {
            connectionState = .signedOut
            return
        }
        guard let url = bootstrapURL() else {
            errorMessage = "Invalid hub URL"
            connectionState = .error
            return
        }

        bootstrapInFlight = true
        isRefreshing = true
        if devices.isEmpty {
            connectionState = .loading
        }

        defer {
            bootstrapInFlight = false
            isRefreshing = false
            if bootstrapQueued {
                let shouldRefreshMetadata = queuedRefreshMetadata
                bootstrapQueued = false
                queuedRefreshMetadata = false
                Task { await self.bootstrap(refreshMetadata: shouldRefreshMetadata) }
            }
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected hub response"
                connectionState = .error
                return
            }

            if http.statusCode == 401 {
                handleUnauthorized(message: "Session expired. Sign in again.")
                return
            }

            guard http.statusCode == 200 else {
                errorMessage = "Hub request failed (\(http.statusCode))"
                connectionState = .degraded
                return
            }

            let bootstrap = try JSONDecoder().decode(BootstrapResponse.self, from: data)
            devices = bootstrap.devices
            selectedDeviceID = resolvedDeviceID(from: bootstrap)
            widgets = bootstrap.layout?.widgets.sorted(by: { $0.order < $1.order }) ?? []
            ensureDefaultPinnedWidgets()
            events = bootstrap.events
            alertSummary = bootstrap.alertSummary
            errorMessage = ""
            connectionState = devices.isEmpty ? .degraded : .ready
            reconnectAttempts = 0
            if refreshMetadata {
                await fetchAlertRules()
                if hasAdminSession {
                    await fetchAdminResources()
                }
            }
            await connectStreamIfNeeded(forceReconnect: forceReconnect)
        } catch {
            errorMessage = error.localizedDescription
            connectionState = devices.isEmpty ? .error : .degraded
        }
    }

    func signInAndCreateClientToken() async {
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let sessionResponse = try await createAdminSession()
            adminSessionToken = sessionResponse.token

            guard let tokenURL = URL(string: "\(baseURL)/api/client-tokens") else {
                errorMessage = "Invalid hub URL"
                connectionState = .error
                return
            }

            var tokenRequest = URLRequest(url: tokenURL)
            tokenRequest.httpMethod = "POST"
            tokenRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            tokenRequest.setValue("Bearer \(sessionResponse.token)", forHTTPHeaderField: "Authorization")
            tokenRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "name": "Mac Menu Bar",
                "kind": target,
            ])

            let (tokenData, tokenResponse) = try await session.data(for: tokenRequest)
            guard let tokenHTTP = tokenResponse as? HTTPURLResponse else {
                errorMessage = "Unexpected token response"
                connectionState = .error
                return
            }
            guard tokenHTTP.statusCode == 200 else {
                errorMessage = "Token creation failed"
                connectionState = .error
                return
            }

            let issued = try JSONDecoder().decode(IssuedClientToken.self, from: tokenData)
            KeychainStore.saveToken(issued.token, service: baseURL)
            passwordInput = ""
            errorMessage = ""
            await bootstrap(forceReconnect: true, refreshMetadata: true)
            await fetchAdminResources()
        } catch {
            errorMessage = error.localizedDescription
            connectionState = .error
        }
    }

    func unlockAdminTools() async {
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let sessionResponse = try await createAdminSession()
            adminSessionToken = sessionResponse.token
            errorMessage = ""
            await fetchAdminResources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAdminData() async {
        if hasAdminSession {
            await fetchAdminResources()
        } else {
            await unlockAdminTools()
        }
    }

    func saveLayout() async {
        guard let device = currentDevice else { return }
        let token = storedClientToken()
        guard !token.isEmpty else {
            errorMessage = "Please sign in first"
            connectionState = .signedOut
            return
        }
        guard let url = URL(string: "\(baseURL)/api/layouts?target=\(target)&deviceId=\(device.id)") else {
            errorMessage = "Invalid hub URL"
            connectionState = .error
            return
        }

        isSavingLayout = true
        defer { isSavingLayout = false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(widgets.sorted(by: { $0.order < $1.order }))

            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected save response"
                connectionState = .error
                return
            }
            if http.statusCode == 401 {
                handleUnauthorized(message: "Layout save failed because the token is no longer valid.")
                return
            }
            guard http.statusCode == 200 else {
                errorMessage = "Save failed"
                connectionState = .degraded
                return
            }
            errorMessage = ""
            await bootstrap(refreshMetadata: true)
        } catch {
            errorMessage = error.localizedDescription
            connectionState = .degraded
        }
    }

    func moveWidget(at index: Int, by delta: Int) {
        let nextIndex = index + delta
        guard nextIndex >= 0, nextIndex < widgets.count else { return }
        var copy = widgets
        copy.swapAt(index, nextIndex)
        widgets = copy.enumerated().map { position, widget in
            var updated = widget
            updated.order = position
            return updated
        }
    }

    func isWidgetPinned(_ widgetID: String) -> Bool {
        pinnedWidgetIDs.contains(widgetID)
    }

    func togglePinnedWidget(_ widgetID: String) {
        let availableIDs = Set(widgets.map(\.id))
        var current = pinnedWidgetIDs.filter { availableIDs.contains($0) }
        if let index = current.firstIndex(of: widgetID) {
            current.remove(at: index)
        } else if widgets.contains(where: { $0.id == widgetID }) {
            current.append(widgetID)
        }
        pinnedWidgetIDs = current
    }

    func movePinnedWidget(at index: Int, by delta: Int) {
        let availableIDs = Set(widgets.map(\.id))
        var current = pinnedWidgetIDs.filter { availableIDs.contains($0) }
        let nextIndex = index + delta
        guard nextIndex >= 0, nextIndex < current.count else { return }
        current.swapAt(index, nextIndex)
        pinnedWidgetIDs = current
    }

    func compactValue(for widget: WidgetItem) -> String {
        guard let device = currentDevice else { return "--" }
        guard let snapshot = device.snapshot else { return "..." }

        switch widget.kind {
        case "overview":
            return device.online ? "Live" : "Off"
        case "cpu-memory":
            return "CPU \(format(snapshot.cpu.usagePercent, "%.0f"))%"
        case "temperature":
            let hottest = snapshot.temperatures.max(by: { $0.celsius < $1.celsius })
            return hottest.map { "\(format($0.celsius, "%.0f"))C" } ?? "--"
        case "battery":
            guard let battery = snapshot.battery else { return "--" }
            return "\(format(battery.percent, "%.0f"))%"
        case "docker":
            let healthy = snapshot.docker.filter(\.healthy).count
            let total = snapshot.docker.count
            return total == 0 ? "0" : "\(healthy)/\(total)"
        case "network":
            let active = snapshot.network.first(where: \.isDefault) ?? snapshot.network.first
            return active.map { "\($0.name)" } ?? "--"
        case "storage":
            let fullest = snapshot.storage.max(by: { $0.usedPct < $1.usedPct })
            return fullest.map { "\(format($0.usedPct, "%.0f"))%" } ?? "--"
        default:
            return "--"
        }
    }

    func compactLabel(for widget: WidgetItem) -> String {
        switch widget.kind {
        case "cpu-memory":
            return "CPU"
        case "temperature":
            return "TMP"
        case "battery":
            return "BAT"
        case "docker":
            return "DOC"
        case "network":
            return "NET"
        case "storage":
            return "DSK"
        default:
            return widget.title.uppercased()
        }
    }

    func acknowledgeEvent(_ eventID: String) async {
        let token = storedClientToken()
        guard !token.isEmpty else {
            connectionState = .signedOut
            return
        }
        guard let url = URL(string: "\(baseURL)/api/events/\(eventID)/ack") else {
            errorMessage = "Invalid hub URL"
            return
        }

        isAcknowledgingEvent = eventID
        defer { isAcknowledgingEvent = "" }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected acknowledge response"
                return
            }
            if http.statusCode == 401 {
                handleUnauthorized(message: "Session expired. Sign in again.")
                return
            }
            guard http.statusCode == 200 else {
                errorMessage = "Acknowledge failed"
                return
            }
            await bootstrap(refreshMetadata: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchAlertRules() async {
        let token = storedClientToken()
        guard !token.isEmpty, let device = currentDevice else {
            alertRules = []
            return
        }
        guard let url = URL(string: "\(baseURL)/api/alerts?deviceId=\(device.id)") else { return }

        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 {
                handleUnauthorized(message: "Session expired. Sign in again.")
                return
            }
            guard http.statusCode == 200 else { return }
            alertRules = try JSONDecoder().decode([AlertRuleItem].self, from: data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveAlertRules() async {
        let token = storedClientToken()
        guard !token.isEmpty else {
            connectionState = .signedOut
            return
        }
        guard let device = currentDevice,
              let url = URL(string: "\(baseURL)/api/alerts?deviceId=\(device.id)") else {
            errorMessage = "Select a device first"
            return
        }

        isSavingAlerts = true
        defer { isSavingAlerts = false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(alertRules)
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected alert save response"
                return
            }
            if http.statusCode == 401 {
                handleUnauthorized(message: "Session expired. Sign in again.")
                return
            }
            guard http.statusCode == 200 else {
                errorMessage = "Saving alert rules failed"
                return
            }
            await fetchAlertRules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addNotificationChannel() {
        notificationChannels.append(
            NotificationChannelItem(
                name: "New ntfy channel",
                enabled: false,
                serverURL: "https://ntfy.sh",
                topic: "replace-me"
            )
        )
    }

    func removeNotificationChannel(_ channelID: String) {
        notificationChannels.removeAll { $0.id == channelID }
        for index in alertRules.indices {
            alertRules[index].channels.removeAll { $0 == channelID }
        }
    }

    func toggleChannel(_ channelID: String, on ruleID: String) {
        guard let index = alertRules.firstIndex(where: { $0.id == ruleID }) else { return }
        if alertRules[index].channels.contains(channelID) {
            alertRules[index].channels.removeAll { $0 == channelID }
        } else {
            alertRules[index].channels.append(channelID)
        }
    }

    func channelName(for channelID: String) -> String {
        notificationChannels.first(where: { $0.id == channelID })?.name ?? "Unknown channel"
    }

    func channelNames(for rule: AlertRuleItem) -> String {
        let names = notificationChannels
            .filter { rule.channels.contains($0.id) }
            .map(\.name)
        return names.isEmpty ? "No channels" : names.joined(separator: ", ")
    }

    func saveNotificationChannels() async {
        guard hasAdminSession else {
            errorMessage = "Unlock admin tools first"
            return
        }
        guard let url = URL(string: "\(baseURL)/api/notification-channels") else {
            errorMessage = "Invalid hub URL"
            return
        }

        isSavingChannels = true
        defer { isSavingChannels = false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(adminSessionToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(notificationChannels)
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected channel save response"
                return
            }
            if http.statusCode == 401 {
                handleAdminUnauthorized()
                return
            }
            guard http.statusCode == 200 else {
                errorMessage = "Saving channels failed"
                return
            }
            await fetchAdminResources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revokeClientToken(_ tokenID: String) async {
        guard hasAdminSession else {
            errorMessage = "Unlock admin tools first"
            return
        }
        guard let url = URL(string: "\(baseURL)/api/client-tokens/\(tokenID)") else {
            errorMessage = "Invalid hub URL"
            return
        }

        revokingTokenID = tokenID
        defer { revokingTokenID = "" }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(adminSessionToken)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Unexpected revoke response"
                return
            }
            if http.statusCode == 401 {
                handleAdminUnauthorized()
                return
            }
            guard http.statusCode == 200 else {
                errorMessage = "Revoke failed"
                return
            }
            await fetchAdminResources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func widgetSummary(for widget: WidgetItem) -> WidgetSummary {
        guard let device = currentDevice else {
            return WidgetSummary(value: "No device selected", detail: nil, symbol: "questionmark.circle")
        }
        guard let snapshot = device.snapshot else {
            return WidgetSummary(value: "No snapshot data yet", detail: nil, symbol: "clock")
        }

        switch widget.kind {
        case "overview":
            return WidgetSummary(
                value: device.online ? "Online now" : "Offline or stale",
                detail: snapshot.hostname,
                symbol: device.online ? "checkmark.circle.fill" : "bolt.horizontal.circle.fill"
            )
        case "cpu-memory":
            return WidgetSummary(
                value: "CPU \(format(snapshot.cpu.usagePercent, "%.0f"))%  MEM \(format(snapshot.memory.usedPct, "%.0f"))%",
                detail: "Live utilization",
                symbol: "cpu"
            )
        case "storage":
            let fullest = snapshot.storage.max(by: { $0.usedPct < $1.usedPct })
            return WidgetSummary(
                value: fullest.map { "\($0.path) \(format($0.usedPct, "%.0f"))%" } ?? "No disk data",
                detail: "Most-used volume",
                symbol: "internaldrive"
            )
        case "network":
            let active = snapshot.network.first(where: \.isDefault) ?? snapshot.network.first
            if let active {
                return WidgetSummary(
                    value: "\(active.name) RX \(formatBytes(active.rxBytes))",
                    detail: "TX \(formatBytes(active.txBytes))",
                    symbol: "network"
                )
            }
            return WidgetSummary(value: "No network data", detail: nil, symbol: "network.slash")
        case "temperature":
            let hottest = snapshot.temperatures.max(by: { $0.celsius < $1.celsius })
            return WidgetSummary(
                value: hottest.map { "\(format($0.celsius, "%.1f")) C" } ?? "No sensor",
                detail: hottest?.name,
                symbol: "thermometer.medium"
            )
        case "battery":
            guard let battery = snapshot.battery else {
                return WidgetSummary(value: "No battery", detail: nil, symbol: "battery.0")
            }
            return WidgetSummary(
                value: "Battery \(format(battery.percent, "%.0f"))%",
                detail: battery.charging ? "Charging" : "On battery",
                symbol: battery.charging ? "battery.100.bolt" : "battery.75"
            )
        case "docker":
            let healthy = snapshot.docker.filter(\.healthy).count
            let total = snapshot.docker.count
            return WidgetSummary(
                value: total == 0 ? "No containers" : "\(healthy)/\(total) healthy",
                detail: total == 0 ? nil : "Docker services",
                symbol: "shippingbox"
            )
        default:
            return WidgetSummary(value: snapshot.hostname, detail: "Live host", symbol: "server.rack")
        }
    }

    private func bootstrapURL() -> URL? {
        var path = "\(baseURL)/api/bootstrap?target=\(target)"
        if !selectedDeviceID.isEmpty {
            path += "&deviceId=\(selectedDeviceID)"
        }
        return URL(string: path)
    }

    private func resolvedDeviceID(from response: BootstrapResponse) -> String {
        if !selectedDeviceID.isEmpty && response.devices.contains(where: { $0.id == selectedDeviceID }) {
            return selectedDeviceID
        }
        if let explicit = response.device?.id {
            return explicit
        }
        return response.devices.first?.id ?? ""
    }

    private func ensureDefaultPinnedWidgets() {
        let available = widgets.filter(\.visible)
        let availableIDs = Set(available.map(\.id))
        let filtered = pinnedWidgetIDs.filter { availableIDs.contains($0) }
        if !filtered.isEmpty {
            pinnedWidgetIDs = filtered
            return
        }

        let preferredKinds = ["battery", "cpu-memory", "temperature"]
        let defaults = preferredKinds.compactMap { kind in
            available.first(where: { $0.kind == kind })?.id
        }
        pinnedWidgetIDs = defaults
    }

    private var pinnedScopeKey: String {
        let deviceKey = selectedDeviceID.isEmpty ? "default-device" : selectedDeviceID
        return "\(baseURL)::\(deviceKey)"
    }

    private func scheduleBootstrap(immediate: Bool = false, forceReconnect: Bool = false, refreshMetadata: Bool = false) {
        scheduledBootstrapTask?.cancel()
        scheduledBootstrapTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard let self else { return }
            await self.bootstrap(forceReconnect: forceReconnect, refreshMetadata: refreshMetadata)
        }
    }

    private func handleUnauthorized(message: String) {
        KeychainStore.deleteToken(service: baseURL)
        disconnectStream()
        passwordInput = ""
        devices = []
        widgets = []
        events = []
        alertRules = []
        notificationChannels = []
        clientTokens = []
        alertSummary = AlertSummary(activeCount: 0, highestLevel: "healthy", latestMessage: nil)
        selectedDeviceID = ""
        errorMessage = message
        connectionState = .signedOut
        adminSessionToken = ""
    }

    private func handleAdminUnauthorized() {
        adminSessionToken = ""
        notificationChannels = []
        clientTokens = []
        errorMessage = "Admin session expired. Enter the admin password again."
    }

    private func createAdminSession() async throws -> SessionResponse {
        guard let loginURL = URL(string: "\(baseURL)/api/sessions") else {
            throw URLError(.badURL)
        }

        var loginRequest = URLRequest(url: loginURL)
        loginRequest.httpMethod = "POST"
        loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        loginRequest.httpBody = try JSONSerialization.data(withJSONObject: ["password": passwordInput])

        let (sessionData, loginResponse) = try await session.data(for: loginRequest)
        guard let loginHTTP = loginResponse as? HTTPURLResponse else {
            throw NSError(domain: "StatusHub", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected login response"])
        }
        guard loginHTTP.statusCode == 200 else {
            let message = loginHTTP.statusCode == 401 ? "Login failed" : "Could not create session"
            throw NSError(domain: "StatusHub", code: loginHTTP.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(SessionResponse.self, from: sessionData)
    }

    private func fetchAdminResources() async {
        guard hasAdminSession else {
            notificationChannels = []
            clientTokens = []
            return
        }

        isLoadingAdminData = true
        defer { isLoadingAdminData = false }

        async let channels = loadAdminResource(
            path: "/api/notification-channels",
            type: [NotificationChannelItem].self
        )
        async let tokens = loadAdminResource(
            path: "/api/client-tokens",
            type: [ClientTokenItem].self
        )

        do {
            notificationChannels = try await channels
            clientTokens = try await tokens
            errorMessage = ""
        } catch {
            if (error as NSError).code == 401 {
                handleAdminUnauthorized()
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadAdminResource<T: Decodable>(path: String, type: T.Type) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(adminSessionToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "StatusHub", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected admin response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "StatusHub", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Admin request failed"])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func connectStreamIfNeeded(forceReconnect: Bool) async {
        let token = storedClientToken()
        guard !token.isEmpty else { return }
        guard let streamURL = makeStreamURL(token: token) else {
            errorMessage = "Invalid stream URL"
            connectionState = .error
            return
        }

        if forceReconnect || currentStreamURL != streamURL || streamTask == nil {
            disconnectStream()
            currentStreamURL = streamURL
            let task = session.webSocketTask(with: streamURL)
            streamTask = task
            streamConnected = true
            task.resume()
            listenTask = Task { [weak self, weak task] in
                guard let self, let task else { return }
                await self.listen(to: task)
            }
        }
    }

    private func makeStreamURL(token: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/stream"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    private func disconnectStream() {
        scheduledBootstrapTask?.cancel()
        reconnectTask?.cancel()
        listenTask?.cancel()
        streamTask?.cancel(with: .goingAway, reason: nil)
        listenTask = nil
        reconnectTask = nil
        streamTask = nil
        currentStreamURL = nil
        streamConnected = false
    }

    private func listen(to task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                _ = try await task.receive()
                reconnectAttempts = 0
                streamConnected = true
                if connectionState == .degraded || connectionState == .error {
                    connectionState = devices.isEmpty ? .loading : .ready
                }
                scheduleBootstrap(refreshMetadata: false)
            } catch {
                guard task === streamTask else { return }
                streamConnected = false
                connectionState = devices.isEmpty ? .error : .degraded
                scheduleReconnect()
                return
            }
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectAttempts += 1
        let delaySeconds = min(pow(2.0, Double(max(0, reconnectAttempts - 1))), 30.0)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let self, self.hasStoredToken else { return }
            await self.bootstrap(forceReconnect: true)
        }
    }
}
