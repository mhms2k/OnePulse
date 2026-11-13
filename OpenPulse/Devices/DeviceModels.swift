import Foundation
import Security

enum DeviceKind: String, Codable, CaseIterable {
    case cmfWatch
    case heartRateSensor

    var title: String {
        switch self {
        case .cmfWatch: return "CMF / Nothing Watch"
        case .heartRateSensor: return "Heart rate sensor"
        }
    }

    var symbol: String {
        switch self {
        case .cmfWatch: return "applewatch.side.right"
        case .heartRateSensor: return "heart.circle"
        }
    }

    var capabilities: String {
        switch self {
        case .cmfWatch: return "Sleep stages · all-day heart rate · SpO₂ · stress · steps · workouts"
        case .heartRateSensor: return "Live heart rate · beat-to-beat HRV · strain"
        }
    }
}

/// A device the user has paired with OpenPulse.
struct KnownDevice: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var kind: DeviceKind
    var lastSync: Date?
    var battery: Int?
    var firmware: String?
    var serial: String?
    var autoConnect: Bool = true

    private static let key = "openpulse.devices.v1"

    static func loadAll() -> [KnownDevice] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([KnownDevice].self, from: data) else { return [] }
        return list
    }

    static func saveAll(_ list: [KnownDevice]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Settings the app pushes to a CMF watch after connecting.
struct WatchSettings: Codable, Equatable {
    var allDayHeartRate = true
    var spo2Monitoring = true
    var stressMonitoring = true

    private static let key = "openpulse.watchSettings.v1"
    static func load() -> WatchSettings {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(WatchSettings.self, from: d) else { return WatchSettings() }
        return s
    }
    func save() { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) } }
}

/// Minimal Keychain wrapper for per-watch pairing keys.
enum Keychain {
    private static let service = "app.openpulse.pairing"

    static func set(_ bytes: [UInt8], for account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(bytes)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> [UInt8]? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return [UInt8](data)
    }

    static func remove(_ account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

/// One line of the Bluetooth debug log (raw packets are invaluable for decoding new firmware).
struct LogLine: Identifiable, Hashable {
    enum Direction: String { case tx = "→", rx = "←", info = "•", error = "!" }
    let id = UUID()
    let date = Date()
    let direction: Direction
    let device: String
    let text: String

    var formatted: String {
        "\(date.formatted(.dateTime.hour().minute().second())) \(direction.rawValue) [\(device)] \(text)"
    }
}
