import Foundation

/// Weekly goals, like WHOOP's Weekly Plan.
struct WeeklyPlan: Codable, Equatable {
    var sleepHours: Double = 7.5
    var workouts: Int = 3
    var strengthMinutes: Int = 90
    var dailySteps: Int = 8000
}

struct WeeklyProgress {
    var daysElapsed: Int
    var workouts: Int
    var strengthMinutes: Double
    var sleepHours: Double?
    var dailySteps: Double?
}

struct WeekAverages {
    var recovery: Double?
    var strain: Double?
    var sleepHours: Double?
    var restingHR: Double?
}

enum WeeklyReport {
    /// Progress for the current calendar week (Monday or Sunday start, per the phone's region).
    static func progress(scores: [DayScore], strength: [StrengthWorkout], now: Date = Date()) -> WeeklyProgress {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        let days = scores.filter { $0.day >= start && $0.day <= now }
        let logged = strength.filter { $0.start >= start && $0.start <= now }
        let tracked = days.flatMap(\.workouts).filter { w in
            !logged.contains { $0.start < w.end && w.start < $0.end }
        }
        let elapsed = (cal.dateComponents([.day], from: start, to: cal.startOfDay(for: now)).day ?? 0) + 1
        return WeeklyProgress(
            daysElapsed: min(7, max(1, elapsed)),
            workouts: tracked.count + logged.count,
            strengthMinutes: Healthspan.strengthMinutes(strength: strength, days: days, from: start),
            sleepHours: Stats.mean(days.filter(\.hasSleep).map { $0.asleep / 3600 }),
            dailySteps: Stats.mean(days.map { Double($0.steps) }.filter { $0 > 0 })
        )
    }

    /// The last 7 days compared with the 7 days before.
    static func compare(scores: [DayScore], now: Date = Date()) -> (current: WeekAverages, previous: WeekAverages) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let weekAgo = cal.date(byAdding: .day, value: -6, to: today) ?? today
        let twoWeeksAgo = cal.date(byAdding: .day, value: -13, to: today) ?? today
        let current = scores.filter { $0.day >= weekAgo && $0.day <= today }
        let previous = scores.filter { $0.day >= twoWeeksAgo && $0.day < weekAgo }
        return (averages(current), averages(previous))
    }

    static func averages(_ days: [DayScore]) -> WeekAverages {
        WeekAverages(recovery: Stats.mean(days.compactMap(\.recovery)),
                     strain: Stats.mean(days.filter { $0.avgHR != nil }.map(\.strain)),
                     sleepHours: Stats.mean(days.filter(\.hasSleep).map { $0.asleep / 3600 }),
                     restingHR: Stats.mean(days.compactMap(\.restingHR)))
    }
}
