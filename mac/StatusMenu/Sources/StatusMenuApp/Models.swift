import Foundation
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
    let storage: [Disk]
    let network: [NetworkAdapter]
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

struct Disk: Decodable {
    let path: String
    let usedPct: Double
}

struct NetworkAdapter: Decodable {
    let name: String
    let rxBytes: UInt64
    let txBytes: UInt64
    let isDefault: Bool
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
    let createdAt: String
    let acknowledgedAt: String?
}

struct BootstrapResponse: Decodable {
    let devices: [DeviceSummary]
    let device: DeviceSummary?
    let layout: LayoutResponse?
    let alertSummary: AlertSummary
    let events: [EventSummary]
}

enum ConnectionState: String {
    case signedOut
    case loading
    case ready
    case degraded
    case error
}

struct WidgetSummary {
    let value: String
    let detail: String?
    let symbol: String
}

struct AlertRuleItem: Codable, Identifiable {
    let id: String
    let deviceId: String
    var title: String
    let metric: String
    let condition: String
    var threshold: Double
    var duration: Int
    var severity: String
    var channels: [String]
    var enabled: Bool
    let resolveBehavior: String
}

struct NotificationChannelItem: Codable, Identifiable {
    let id: String
    var kind: String
    var name: String
    var enabled: Bool
    var serverURL: String
    var topic: String

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case enabled
        case config
    }

    init(id: String = UUID().uuidString, kind: String = "ntfy", name: String, enabled: Bool, serverURL: String, topic: String) {
        self.id = id
        self.kind = kind
        self.name = name
        self.enabled = enabled
        self.serverURL = serverURL
        self.topic = topic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        let config = try container.decodeIfPresent([String: String].self, forKey: .config) ?? [:]
        serverURL = config["serverURL"] ?? ""
        topic = config["topic"] ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(enabled, forKey: .enabled)
        try container.encode([
            "serverURL": serverURL,
            "topic": topic,
        ], forKey: .config)
    }
}

struct ClientTokenItem: Decodable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let createdAt: String
    let lastUsedAt: String?
    let revoked: Bool
}

func format(_ value: Double, _ specifier: String) -> String {
    String(format: specifier, value)
}

func formatBytes(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
}

func formatTimestamp(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "Never" }
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: value) else { return value }
    return date.formatted(date: .abbreviated, time: .shortened)
}
