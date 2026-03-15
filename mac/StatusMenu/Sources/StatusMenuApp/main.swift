import Security
import SwiftUI

struct SessionResponse: Decodable {
    let token: String
}

struct IssuedClientToken: Decodable {
    let id: String
    let name: String
    let kind: String
    let token: String
}

struct DeviceSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let online: Bool
    let alertState: String
    let snapshot: Snapshot?
}

struct Snapshot: Decodable {
    let hostname: String
    let cpu: CPU
    let memory: Memory
    let battery: Battery?
    let temperatures: [Temperature]
    let docker: [Container]
}

struct CPU: Decodable {
    let usagePercent: Double
}

struct Memory: Decodable {
    let usedPct: Double
}

struct Battery: Decodable {
    let percent: Double
    let charging: Bool
}

struct Temperature: Decodable {
    let name: String
    let celsius: Double
}

struct Container: Decodable {
    let name: String
    let status: String
    let healthy: Bool
}

struct WidgetItem: Decodable, Encodable, Identifiable {
    let id: String
    let kind: String
    let deviceId: String
    var title: String
    var visible: Bool
    var order: Int
    let size: String
}

struct LayoutResponse: Decodable {
    let id: String
    let deviceId: String
    let target: String
    let widgets: [WidgetItem]
}

struct AlertSummary: Decodable {
    let activeCount: Int
    let highestLevel: String
    let latestMessage: String?
}

struct EventSummary: Decodable, Identifiable {
    let id: String
    let title: String
    let body: String
    let severity: String
    let acknowledgedAt: String?
}

struct BootstrapResponse: Decodable {
    let devices: [DeviceSummary]
    let device: DeviceSummary?
    let layout: LayoutResponse?
    let alertSummary: AlertSummary
    let events: [EventSummary]
}

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
    @Published var passwordInput = ""
    @Published var devices: [DeviceSummary] = []
    @Published var widgets: [WidgetItem] = []
    @Published var events: [EventSummary] = []
    @Published var alertSummary = AlertSummary(activeCount: 0, highestLevel: "healthy", latestMessage: nil)
    @Published var errorMessage = ""

    private var streamTask: URLSessionWebSocketTask?
    private let target = "mac_menu_bar"

    var currentDevice: DeviceSummary? {
        devices.first(where: { $0.id == selectedDeviceID }) ?? devices.first
    }

    var iconName: String {
        switch alertSummary.highestLevel {
        case "critical":
            return "exclamationmark.triangle.fill"
        case "warning":
            return "exclamationmark.circle.fill"
        default:
            return currentDevice?.online == false ? "bolt.horizontal.circle.fill" : "server.rack"
        }
    }

    func storedClientToken() -> String {
        KeychainStore.loadToken(service: baseURL)
    }

    func clearSession() {
        KeychainStore.deleteToken(service: baseURL)
        passwordInput = ""
        devices = []
        widgets = []
        events = []
        errorMessage = ""
        streamTask?.cancel(with: .goingAway, reason: nil)
        streamTask = nil
    }

    func bootstrap() async {
        let token = storedClientToken()
        guard !token.isEmpty else { return }
        var path = "\(baseURL)/api/bootstrap?target=\(target)"
        if !selectedDeviceID.isEmpty {
            path += "&deviceId=\(selectedDeviceID)"
        }
        guard let url = URL(string: path) else {
            errorMessage = "Invalid hub URL"
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                errorMessage = "Hub request failed"
                return
            }
            let bootstrap = try JSONDecoder().decode(BootstrapResponse.self, from: data)
            devices = bootstrap.devices
            if selectedDeviceID.isEmpty {
                selectedDeviceID = bootstrap.device?.id ?? bootstrap.devices.first?.id ?? ""
            }
            widgets = bootstrap.layout?.widgets.sorted(by: { $0.order < $1.order }) ?? []
            events = bootstrap.events
            alertSummary = bootstrap.alertSummary
            errorMessage = ""
            connectStreamIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInAndCreateClientToken() async {
        guard let loginURL = URL(string: "\(baseURL)/api/sessions") else {
            errorMessage = "Invalid hub URL"
            return
        }
        do {
            var loginRequest = URLRequest(url: loginURL)
            loginRequest.httpMethod = "POST"
            loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            loginRequest.httpBody = try JSONSerialization.data(withJSONObject: ["password": passwordInput])
            let (sessionData, loginResponse) = try await URLSession.shared.data(for: loginRequest)
            guard let loginHTTP = loginResponse as? HTTPURLResponse, loginHTTP.statusCode == 200 else {
                errorMessage = "Login failed"
                return
            }
            let session = try JSONDecoder().decode(SessionResponse.self, from: sessionData)

            guard let tokenURL = URL(string: "\(baseURL)/api/client-tokens") else {
                errorMessage = "Invalid hub URL"
                return
            }
            var tokenRequest = URLRequest(url: tokenURL)
            tokenRequest.httpMethod = "POST"
            tokenRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            tokenRequest.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
            tokenRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "name": "Mac Menu Bar",
                "kind": target,
            ])
            let (tokenData, tokenResponse) = try await URLSession.shared.data(for: tokenRequest)
            guard let tokenHTTP = tokenResponse as? HTTPURLResponse, tokenHTTP.statusCode == 200 else {
                errorMessage = "Token creation failed"
                return
            }
            let issued = try JSONDecoder().decode(IssuedClientToken.self, from: tokenData)
            KeychainStore.saveToken(issued.token, service: baseURL)
            passwordInput = ""
            await bootstrap()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveLayout() async {
        guard let device = currentDevice else { return }
        let token = storedClientToken()
        guard !token.isEmpty else {
            errorMessage = "Please sign in first"
            return
        }
        guard let url = URL(string: "\(baseURL)/api/layouts?target=\(target)&deviceId=\(device.id)") else {
            errorMessage = "Invalid hub URL"
            return
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(widgets.sorted(by: { $0.order < $1.order }))
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                errorMessage = "Save failed"
                return
            }
            await bootstrap()
        } catch {
            errorMessage = error.localizedDescription
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

    func connectStreamIfNeeded() {
        guard streamTask == nil else { return }
        let token = storedClientToken()
        guard !token.isEmpty else { return }
        guard var components = URLComponents(string: baseURL) else { return }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/stream"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        streamTask = task
        task.resume()
        listen(task)
    }

    private func listen(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                Task { @MainActor in
                    self.streamTask = nil
                }
            case .success:
                Task { @MainActor in
                    await self.bootstrap()
                    self.listen(task)
                }
            }
        }
    }

    func widgetValue(_ widget: WidgetItem) -> String {
        guard let device = currentDevice else { return "No device" }
        switch widget.kind {
        case "overview":
            return device.online ? "Online now" : "Offline or stale"
        case "cpu-memory":
            guard let snapshot = device.snapshot else { return "No data" }
            return "CPU \(format(snapshot.cpu.usagePercent, "%.0f"))%  Memory \(format(snapshot.memory.usedPct, "%.0f"))%"
        case "temperature":
            return device.snapshot?.temperatures.first.map { "\(format($0.celsius, "%.1f")) C" } ?? "No sensor"
        case "battery":
            guard let battery = device.snapshot?.battery else { return "No battery" }
            return "Battery \(format(battery.percent, "%.0f"))% \(battery.charging ? "charging" : "")"
        case "docker":
            let healthy = device.snapshot?.docker.filter(\.healthy).count ?? 0
            let total = device.snapshot?.docker.count ?? 0
            return total == 0 ? "No containers" : "Docker \(healthy)/\(total) healthy"
        default:
            return device.snapshot?.hostname ?? "Live"
        }
    }
}

func format(_ value: Double, _ specifier: String) -> String {
    String(format: specifier, value)
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Status Hub Settings")
                .font(.title3.bold())

            TextField("Hub URL", text: $model.baseURL)
                .textFieldStyle(.roundedBorder)

            SecureField("Admin password", text: $model.passwordInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Create secure client token") {
                    Task { await model.signInAndCreateClientToken() }
                }
                Button("Forget token") {
                    model.clearSession()
                }
            }

            if !model.devices.isEmpty {
                Picker("Device", selection: $model.selectedDeviceID) {
                    ForEach(model.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .onChange(of: model.selectedDeviceID) { _, _ in
                    Task { await model.bootstrap() }
                }
            }

            Divider()

            Text("Menu Bar Layout")
                .font(.headline)

            ForEach(Array(model.widgets.enumerated()), id: \.element.id) { index, widget in
                HStack {
                    Toggle(widget.title, isOn: Binding(
                        get: { model.widgets[index].visible },
                        set: { model.widgets[index].visible = $0 }
                    ))
                    Spacer()
                    Button("Up") { model.moveWidget(at: index, by: -1) }
                    Button("Down") { model.moveWidget(at: index, by: 1) }
                }
            }

            Button("Save layout") {
                Task { await model.saveLayout() }
            }

            if !model.errorMessage.isEmpty {
                Text(model.errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding()
        .frame(width: 420)
        .task {
            await model.bootstrap()
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Status Hub")
                    .font(.headline)
                Spacer()
                Text(model.alertSummary.highestLevel.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let device = model.currentDevice {
                Text(device.name)
                    .font(.subheadline.bold())
                Text(device.online ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundStyle(device.online ? .green : .orange)
            } else {
                Text("No device connected yet")
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(model.widgets.filter(\.visible).sorted(by: { $0.order < $1.order })) { widget in
                VStack(alignment: .leading, spacing: 2) {
                    Text(widget.title)
                        .font(.caption.bold())
                    Text(model.widgetValue(widget))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ForEach(model.events.prefix(3)) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.caption.bold())
                    Text(event.body)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Refresh") {
                    Task { await model.bootstrap() }
                }
                SettingsLink {
                    Text("Settings")
                }
            }

            if !model.errorMessage.isEmpty {
                Text(model.errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding()
        .frame(width: 340)
        .task {
            await model.bootstrap()
        }
    }
}

@main
struct StatusMenuApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Status", systemImage: model.iconName) {
            MenuContentView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
