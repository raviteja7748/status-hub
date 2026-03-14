import SwiftUI

struct SessionResponse: Decodable {
    let token: String
}

struct DeviceSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let lastSeen: String
    let online: Bool
    let alertState: String
    let snapshot: Snapshot?
}

struct Snapshot: Decodable {
    let hostname: String
    let cpu: CPU
    let memory: Memory
    let battery: Battery?
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

struct Container: Decodable {
    let name: String
    let status: String
}

@MainActor
final class AppModel: ObservableObject {
    @AppStorage("baseURL") var baseURL = "http://localhost:8080"
    @AppStorage("token") var token = ""
    @AppStorage("password") var password = ""
    @Published var devices: [DeviceSummary] = []
    @Published var errorMessage = ""

    func refresh() async {
        guard !token.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/devices") else {
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
            devices = try JSONDecoder().decode([DeviceSummary].self, from: data)
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func login() async {
        guard let url = URL(string: "\(baseURL)/api/sessions") else {
            errorMessage = "Invalid hub URL"
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["password": password])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                errorMessage = "Login failed"
                return
            }
            token = try JSONDecoder().decode(SessionResponse.self, from: data).token
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status Hub")
                .font(.headline)

            TextField("Hub URL", text: $model.baseURL)
                .textFieldStyle(.roundedBorder)
            SecureField("Admin password", text: $model.password)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Sign in") {
                    Task { await model.login() }
                }
                Button("Refresh") {
                    Task { await model.refresh() }
                }
            }

            if !model.errorMessage.isEmpty {
                Text(model.errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Divider()

            if model.devices.isEmpty {
                Text("No devices connected yet")
                    .foregroundStyle(.secondary)
            }

            ForEach(model.devices.prefix(3)) { device in
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.subheadline.bold())
                    Text(device.online ? "Online" : "Offline")
                        .font(.caption)
                        .foregroundStyle(device.online ? .green : .orange)
                    if let snapshot = device.snapshot {
                        Text("CPU \(snapshot.cpu.usagePercent, specifier: "%.0f")%  Memory \(snapshot.memory.usedPct, specifier: "%.0f")%")
                            .font(.caption)
                        if let battery = snapshot.battery {
                            Text("Battery \(battery.percent, specifier: "%.0f")% \(battery.charging ? "charging" : "")")
                                .font(.caption)
                        }
                        if let container = snapshot.docker.first {
                            Text("Docker: \(container.name) \(container.status)")
                                .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if let url = URL(string: model.baseURL) {
                Link("Open full dashboard", destination: url)
            }
        }
        .padding()
        .frame(width: 340)
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }
}

@main
struct StatusMenuApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Status", systemImage: "server.rack") {
            MenuContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
