import Foundation

struct StrengthSet: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var exercise: String
    var reps: Int
    var weightKg: Double

    var volume: Double { Double(reps) * weightKg }
    /// Epley estimate of the one-rep max.
    var estimatedOneRepMax: Double { reps <= 1 ? weightKg : weightKg * (1 + Double(reps) / 30) }
}

struct StrengthWorkout: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var start: Date
    var end: Date
    var sets: [StrengthSet] = []
    var source: String = "User"

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var volume: Double { sets.reduce(0) { $0 + $1.volume } }
    var exercises: [String] {
        var seen: [String] = []
        for s in sets where !seen.contains(s.exercise) { seen.append(s.exercise) }
        return seen
    }

    static func new(now: Date = Date()) -> StrengthWorkout {
        StrengthWorkout(name: "Strength session", start: now.addingTimeInterval(-3600), end: now)
    }
}

struct ExerciseRecord: Identifiable, Hashable {
    var id: String { exercise }
    var exercise: String
    var bestWeight: Double
    var bestOneRepMax: Double
    var totalVolume: Double
    var sessions: Int
    var last: Date
}

struct WeekValue: Identifiable, Hashable {
    var id: Date { start }
    var start: Date
    var minutes: Double
}

enum StrengthStats {
    static let library: [String] = [
        "Back Squat", "Front Squat", "Deadlift", "Romanian Deadlift", "Bench Press", "Incline Bench Press",
        "Overhead Press", "Pull-up", "Chin-up", "Barbell Row", "Dumbbell Row", "Lat Pulldown", "Lunge",
        "Hip Thrust", "Leg Press", "Dips", "Push-up", "Bicep Curl", "Tricep Extension", "Kettlebell Swing", "Plank",
    ]

    /// Personal records and totals per exercise, most recently trained first.
    static func records(_ workouts: [StrengthWorkout]) -> [ExerciseRecord] {
        var map: [String: ExerciseRecord] = [:]
        for w in workouts {
            for name in w.exercises {
                var r = map[name] ?? ExerciseRecord(exercise: name, bestWeight: 0, bestOneRepMax: 0,
                                                    totalVolume: 0, sessions: 0, last: .distantPast)
                r.sessions += 1
                r.last = max(r.last, w.start)
                map[name] = r
            }
            for s in w.sets {
                guard var r = map[s.exercise] else { continue }
                r.bestWeight = max(r.bestWeight, s.weightKg)
                r.bestOneRepMax = max(r.bestOneRepMax, s.estimatedOneRepMax)
                r.totalVolume += s.volume
                map[s.exercise] = r
            }
        }
        return map.values.sorted { $0.last > $1.last }
    }

    /// Strength minutes per calendar week, oldest first.
    static func weeklyMinutes(_ workouts: [StrengthWorkout], weeks: Int, now: Date = Date()) -> [WeekValue] {
        let cal = Calendar.current
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<weeks).reversed().compactMap { i -> WeekValue? in
            guard let start = cal.date(byAdding: .weekOfYear, value: -i, to: thisWeek),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let minutes = workouts.filter { $0.start >= start && $0.start < end }.reduce(0.0) { $0 + $1.duration / 60 }
            return WeekValue(start: start, minutes: minutes)
        }
    }

    static func weight(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg)) kg" : String(format: "%.1f kg", kg)
    }
}
