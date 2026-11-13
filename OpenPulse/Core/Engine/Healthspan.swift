import Foundation

/// One input to the body-age estimate. `years` > 0 ages you, < 0 makes you younger.
struct HealthspanMetric: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var symbol: String
    var value: String
    var target: String
    var years: Double
}

struct HealthspanResult: Hashable {
    var bodyAge: Double
    var chronologicalAge: Int
    /// Years of aging per calendar year at your current habits (1.0 = average).
    var paceOfAging: Double
    var metrics: [HealthspanMetric]
    var daysUsed: Int

    var difference: Double { bodyAge - Double(chronologicalAge) }
}

/// WHOOP-Age-style estimate of physiological age from 30 days of habits and fitness:
/// VO₂ max, resting heart rate, sleep hours and consistency, time in heart-rate zones,
/// strength training and daily steps. Each metric adds or removes years; the weights are
/// simple, documented estimates inspired by published longevity research, not a diagnosis.
enum Healthspan {
    static let windowDays = 30
    static let minimumDays = 14

    static func compute(scores: [DayScore], strength: [StrengthWorkout], profile: UserProfile,
                        now: Date = Date()) -> HealthspanResult? {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -windowDays, to: cal.startOfDay(for: now)) ?? now
        let days = scores.filter { $0.day >= from && ($0.hasSleep || $0.avgHR != nil) }
        guard days.count >= minimumDays else { return nil }
        let weeks = Double(days.count) / 7
        var metrics: [HealthspanMetric] = []

        if let rhr = Stats.mean(days.compactMap(\.restingHR)) {
            let vo2 = vo2Max(maxHR: profile.maxHeartRate, restingHR: rhr)
            let expected = expectedVO2Max(age: profile.age, sex: profile.sex)
            metrics.append(HealthspanMetric(name: "VO₂ max (estimated)", symbol: "lungs.fill",
                                            value: "\(Int(vo2.rounded())) ml/kg/min",
                                            target: "\(Int((expected + 5).rounded()))+",
                                            years: Stats.clamp(-(vo2 - expected) / 8 * 2.5, -2.5, 3)))
            metrics.append(HealthspanMetric(name: "Resting heart rate", symbol: "heart.fill",
                                            value: "\(Int(rhr.rounded())) bpm", target: "under 60 bpm",
                                            years: Stats.clamp((rhr - 62) / 15 * 2, -1.5, 2.5)))
        }

        let sleepHours = days.filter(\.hasSleep).map { $0.asleep / 3600 }
        if let h = Stats.mean(sleepHours) {
            metrics.append(HealthspanMetric(name: "Hours of sleep", symbol: "bed.double.fill",
                                            value: String(format: "%.1f h", h), target: "7–9 h",
                                            years: sleepYears(h)))
        }

        if let c = Stats.mean(days.compactMap(\.consistency)) {
            metrics.append(HealthspanMetric(name: "Sleep consistency", symbol: "calendar.badge.clock",
                                            value: "\(Int(c.rounded()))%", target: "80%+",
                                            years: Stats.clamp((75 - c) / 25, -1, 1.5)))
        }

        let lowZones = days.reduce(0.0) { $0 + $1.zoneMinutes.prefix(3).reduce(0, +) } / weeks
        metrics.append(HealthspanMetric(name: "Time in zones 1–3", symbol: "figure.walk",
                                        value: "\(Int(lowZones.rounded())) min/week", target: "150+ min/week",
                                        years: Stats.clamp(1.5 - lowZones / 100, -1.5, 1.5)))

        let highZones = days.reduce(0.0) { $0 + $1.zoneMinutes.suffix(2).reduce(0, +) } / weeks
        metrics.append(HealthspanMetric(name: "Time in zones 4–5", symbol: "figure.run",
                                        value: "\(Int(highZones.rounded())) min/week", target: "30+ min/week",
                                        years: Stats.clamp(0.5 - highZones / 50, -1, 0.5)))

        let strengthMin = strengthMinutes(strength: strength, days: days, from: from) / weeks
        metrics.append(HealthspanMetric(name: "Strength training", symbol: "dumbbell.fill",
                                        value: "\(Int(strengthMin.rounded())) min/week", target: "90+ min/week",
                                        years: Stats.clamp(1 - strengthMin / 60, -1, 1)))

        let steps = days.map { Double($0.steps) }.filter { $0 > 0 }
        if let s = Stats.mean(steps) {
            metrics.append(HealthspanMetric(name: "Daily steps", symbol: "shoeprints.fill",
                                            value: Int(s).formatted(), target: "8,000+",
                                            years: Stats.clamp((7500 - s) / 3000, -1, 1.5)))
        }

        let total = metrics.reduce(0.0) { $0 + $1.years }
        return HealthspanResult(bodyAge: Double(profile.age) + total,
                                chronologicalAge: profile.age,
                                paceOfAging: Stats.clamp(1 + total / 6, -1, 3),
                                metrics: metrics,
                                daysUsed: days.count)
    }

    /// Uth–Sørensen estimate: VO₂ max ≈ 15.3 × HRmax / HRrest.
    static func vo2Max(maxHR: Int, restingHR: Double) -> Double {
        15.3 * Double(maxHR) / max(restingHR, 30)
    }

    /// Rough average VO₂ max for age and sex (declines ~0.25 per year after 30).
    static func expectedVO2Max(age: Int, sex: UserProfile.Sex) -> Double {
        (sex == .female ? 38.0 : 45.0) - 0.25 * Double(age - 30)
    }

    static func sleepYears(_ hours: Double) -> Double {
        switch hours {
        case ..<5: return 2
        case ..<6: return 1
        case ..<7: return 0.3
        case ...9: return -1
        default: return 0.5
        }
    }

    static func isStrengthActivity(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["strength", "functional", "crossfit", "weight", "pilates"].contains { n.contains($0) }
    }

    /// Logged strength sessions plus watch-recorded strength workouts that don't overlap them.
    static func strengthMinutes(strength: [StrengthWorkout], days: [DayScore], from: Date) -> Double {
        let logged = strength.filter { $0.start >= from }
        let loggedMinutes = logged.reduce(0.0) { $0 + $1.duration / 60 }
        let tracked = days.flatMap(\.workouts).filter { w in
            isStrengthActivity(w.activity) && !logged.contains { $0.start < w.end && w.start < $0.end }
        }
        let trackedMinutes = tracked.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }
        return loggedMinutes + trackedMinutes
    }
}
