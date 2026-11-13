import Foundation

struct UserProfile: Codable, Equatable {
    enum Sex: String, Codable, CaseIterable, Identifiable {
        case male, female, other
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var name: String = ""
    var age: Int = 30
    var sex: Sex = .male
    var weightKg: Double = 75
    /// Set to override the age-based estimate.
    var maxHeartRateOverride: Int?
    /// Baseline sleep need before strain, debt and naps are added.
    var baselineSleepHours: Double = 7.75
    /// Typical wake-up time, minutes after midnight (used for bedtime advice until enough nights are recorded).
    var wakeMinutes: Int = 7 * 60
    var hasOnboarded: Bool = false

    /// Tanaka formula: 208 − 0.7 × age.
    var estimatedMaxHeartRate: Int { Int((208 - 0.7 * Double(age)).rounded()) }
    var maxHeartRate: Int { maxHeartRateOverride ?? estimatedMaxHeartRate }

    // MARK: Persistence

    private static let key = "openpulse.profile.v1"

    static func load() -> UserProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(UserProfile.self, from: data) else { return UserProfile() }
        return p
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
