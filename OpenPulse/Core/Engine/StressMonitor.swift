import Foundation

/// A point on the 0–3 stress scale (0–1 low, 1–2 medium, 2–3 high).
struct StressSample: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var level: Double
}

struct StressSummary: Hashable {
    var average: Double
    var low: Double      // share of the day, 0...1
    var medium: Double
    var high: Double
    var latest: StressSample?
}

/// WHOOP-style stress monitor. Uses the watch's own stress index when it reports one;
/// otherwise heart rate relative to your resting heart rate, in 15-minute blocks.
/// Workouts (and 15 minutes after them) are left out, so exercise isn't counted as stress.
enum StressMonitor {
    static func timeline(heartRate: [HRPoint], watchStress: [ValuePoint], restingHR: Double?,
                         workouts: [WorkoutScore], sleep: SleepRecord?) -> [StressSample] {
        func excluded(_ d: Date) -> Bool {
            workouts.contains { d >= $0.start.addingTimeInterval(-300) && d <= $0.end.addingTimeInterval(900) }
        }

        if watchStress.count >= 3 {
            return watchStress
                .filter { !excluded($0.date) }
                .sorted { $0.date < $1.date }
                .map { StressSample(date: $0.date, level: fromWatchIndex($0.value)) }
        }

        guard let rhr = restingHR, rhr > 0 else { return [] }
        var buckets: [Date: [Double]] = [:]
        for p in heartRate where !excluded(p.date) {
            let t = (p.date.timeIntervalSince1970 / 900).rounded(.down) * 900
            buckets[Date(timeIntervalSince1970: t), default: []].append(Double(p.bpm))
        }
        return buckets.keys.sorted().compactMap { d -> StressSample? in
            guard let median = Stats.median(buckets[d] ?? []) else { return nil }
            let asleep = sleep.map { d >= $0.start && d <= $0.end } ?? false
            return StressSample(date: d, level: fromHeartRate(median, restingHR: rhr, asleep: asleep))
        }
    }

    /// The CMF watch reports stress 1–100.
    static func fromWatchIndex(_ value: Double) -> Double {
        Stats.clamp((value - 10) / 90 * 3, 0, 3)
    }

    /// Heart rate elevation above resting, beyond what is normal for being awake (or asleep).
    static func fromHeartRate(_ bpm: Double, restingHR: Double, asleep: Bool) -> Double {
        let elevation = (bpm - restingHR) / restingHR
        let calm = asleep ? 0.05 : 0.15
        return Stats.clamp((elevation - calm) / 0.45 * 3, 0, 3)
    }

    static func summary(_ samples: [StressSample]) -> StressSummary? {
        guard !samples.isEmpty else { return nil }
        let n = Double(samples.count)
        return StressSummary(average: Stats.mean(samples.map(\.level)) ?? 0,
                             low: Double(samples.filter { $0.level < 1 }.count) / n,
                             medium: Double(samples.filter { $0.level >= 1 && $0.level < 2 }.count) / n,
                             high: Double(samples.filter { $0.level >= 2 }.count) / n,
                             latest: samples.last)
    }

    static func label(_ level: Double) -> String {
        level < 1 ? "Low" : (level < 2 ? "Medium" : "High")
    }
}
