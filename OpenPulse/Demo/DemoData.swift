import Foundation

/// Generates six weeks of realistic, internally consistent data so every screen
/// can be explored in the simulator before a real watch is paired.
enum DemoData {
    static let source = "Demo"

    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    static func generate(days: Int = 42, now: Date = Date()) -> HealthBatch {
        var rng = SeededRNG(state: 42)
        func r(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }

        let cal = Calendar.current
        var batch = HealthBatch(source: source)
        let today = cal.startOfDay(for: now)
        var fatigue = 0.0  // carries over: hard days and short nights raise it

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = cal.component(.weekday, from: day)
            let weekend = weekday == 1 || weekday == 7

            // ---- Night ending this morning -------------------------------------
            let bedMinutes = (weekend ? 23.8 : 23.0) * 60 + r(-35...35)
            let sleepHours = Swift.max(5.2, Swift.min(9.2, (weekend ? 8.5 : 7.75) + r(-1.0...0.8) - fatigue * 0.3))
            let bed = day.addingTimeInterval(-24 * 3600 + bedMinutes * 60)
            let wake = bed.addingTimeInterval(sleepHours * 3600 + r(10...30) * 60)
            let nightComplete = wake <= now
            let segments = hypnogram(start: bed, end: wake, rng: &rng)
            if nightComplete {
                batch.sleep.append(SleepRecord(start: bed, end: wake, segments: segments, source: source))
            }

            let alcohol = drankAlcohol(nightBefore: day, offset: offset)
            let rhr = 52 + fatigue * 4 + r(-1.5...1.5) + (alcohol ? 4 : 0)
            let hrvMean = 62 - fatigue * 9 + r(-5...5) - (alcohol ? 14 : 0)
            var t = bed
            while t < Swift.min(wake, now) {
                let progress = t.timeIntervalSince(bed) / wake.timeIntervalSince(bed)
                let dip = sin(progress * .pi) * 4 // lowest in the middle of the night
                batch.heartRate.append(HRPoint(date: t, bpm: Int(rhr + 3 - dip + r(-2...3))))
                if Int(t.timeIntervalSince(bed)) % 1800 < 300 {
                    batch.spo2.append(ValuePoint(date: t, value: (96.5 + r(-1.2...1.5)).rounded()))
                    batch.stress.append(ValuePoint(date: t, value: (24 + fatigue * 8 + (alcohol ? 12 : 0) + r(-6...6)).rounded()))
                    batch.hrv.append(ValuePoint(date: t, value: Swift.max(18, hrvMean + r(-12...12))))
                }
                t = t.addingTimeInterval(300)
            }

            // ---- Day ------------------------------------------------------------
            let workoutDay = [2, 4, 6, 7].contains(weekday) && r(0...1) > 0.15
            let hard = workoutDay && r(0...1) > 0.55
            let workoutStart = day.addingTimeInterval((weekend ? 10 : 18) * 3600 + r(0...40) * 60)
            let workoutLength = (hard ? 70.0 : 45.0) + r(-10...15)
            let workoutEnd = workoutStart.addingTimeInterval(workoutLength * 60)
            let activity = hard ? "Outdoor Run" : (r(0...1) > 0.5 ? "Strength Training" : "Outdoor Cycle")

            var dayStrainProxy = 0.0
            t = wake.addingTimeInterval(600)
            let dayEnd = Swift.min(day.addingTimeInterval(23 * 3600), now)
            while t < dayEnd {
                let hour = cal.component(.hour, from: t)
                var bpm = rhr + 18 + r(-6...10)
                if (8...9).contains(hour) || (17...18).contains(hour) { bpm += r(0...25) } // commute / errands
                if workoutDay, t >= workoutStart, t <= workoutEnd {
                    bpm = (hard ? 158 : 132) + r(-10...12)
                    dayStrainProxy += hard ? 1.2 : 0.6
                }
                batch.heartRate.append(HRPoint(date: t, bpm: Int(bpm)))
                if t < workoutStart || t > workoutEnd, Int(t.timeIntervalSince(day)) % 3600 < 300 {
                    batch.stress.append(ValuePoint(date: t, value: (38 + fatigue * 6 + r(-12...14)).rounded()))
                }
                if Int(t.timeIntervalSince(day)) % 3600 < 300 {
                    let steps = Int((hour >= 8 && hour <= 20 ? 700 : 150) + r(0...600))
                    batch.steps.append(StepPoint(date: t, steps: steps, distance: Int(Double(steps) * 0.75),
                                                 calories: steps / 25))
                }
                // Sample every 2 minutes during workouts, every 5 otherwise.
                let inWorkout = workoutDay && t >= workoutStart.addingTimeInterval(-300) && t <= workoutEnd
                t = t.addingTimeInterval(inWorkout ? 120 : 300)
            }
            if workoutDay, workoutEnd <= now {
                batch.workouts.append(WorkoutRecord(start: workoutStart, end: workoutEnd, activity: activity, source: source))
            }

            fatigue = Swift.max(0, Swift.min(2.5, fatigue * 0.55 + dayStrainProxy / 40 + (7.5 - sleepHours) * 0.25))
        }
        return batch
    }

    /// Demo habit: drinks on most Friday/Saturday nights and the odd weekday.
    static func drankAlcohol(nightBefore day: Date, offset: Int) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: day)
        if weekday == 7 || weekday == 1 { return offset % 3 != 0 }
        return offset % 9 == 4
    }

    /// Journal answers matching the generated data (alcohol nights really do lower recovery).
    static func journal(days: Int = 42, now: Date = Date()) -> [Date: [String: Bool]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out: [Date: [String: Bool]] = [:]
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            if offset % 8 == 5 { continue } // forgot to journal that day
            let weekday = cal.component(.weekday, from: day)
            let alcohol = drankAlcohol(nightBefore: day, offset: offset)
            out[day] = [
                "alcohol": alcohol,
                "lateCaffeine": offset % 4 == 1,
                "lateMeal": alcohol || offset % 6 == 0,
                "hydrated": !alcohol || offset % 2 == 0,
                "screens": offset % 3 == 0,
                "stressed": (2...6).contains(weekday) && offset % 5 == 0,
            ]
        }
        return out
    }

    /// Two strength sessions a week with steady progression.
    static func strengthWorkouts(days: Int = 42, now: Date = Date()) -> [StrengthWorkout] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out: [StrengthWorkout] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = cal.component(.weekday, from: day)
            guard weekday == 2 || weekday == 5 else { continue } // Monday and Thursday mornings
            let start = day.addingTimeInterval(7.5 * 3600)
            let end = start.addingTimeInterval(55 * 60)
            guard end <= now else { continue }
            let progress = Double(days - offset) / 7 * 2.5
            let lifts: [(String, Double, Int)] = weekday == 2
                ? [("Back Squat", 80, 5), ("Bench Press", 60, 5), ("Barbell Row", 55, 8)]
                : [("Deadlift", 100, 5), ("Overhead Press", 40, 6), ("Pull-up", 0, 8)]
            var sets: [StrengthSet] = []
            for (name, base, reps) in lifts {
                let weight = base == 0 ? 0 : ((base + progress) / 2.5).rounded() * 2.5
                for _ in 0..<3 { sets.append(StrengthSet(exercise: name, reps: reps, weightKg: weight)) }
            }
            out.append(StrengthWorkout(name: weekday == 2 ? "Lower + push" : "Pull + press",
                                       start: start, end: end, sets: sets, source: source))
        }
        return out
    }

    /// Realistic ~90-minute cycles: deep sleep early in the night, REM later.
    private static func hypnogram(start: Date, end: Date, rng: inout SeededRNG) -> [SleepSegment] {
        var out: [SleepSegment] = []
        var t = start.addingTimeInterval(Double.random(in: 8...20, using: &rng) * 60) // sleep latency
        out.append(SleepSegment(start: start, duration: t.timeIntervalSince(start), stage: .awake))
        var cycle = 0
        while t < end {
            let early = Double(max(0, 3 - cycle)) / 3
            let plan: [(SleepStage, Double)] = [
                (.light, 25 + Double.random(in: -5...8, using: &rng)),
                (.deep, 10 + 30 * early + Double.random(in: -5...5, using: &rng)),
                (.light, 15 + Double.random(in: -4...6, using: &rng)),
                (.rem, 10 + Double(cycle) * 7 + Double.random(in: -4...6, using: &rng)),
                (.awake, Double.random(in: 0...1, using: &rng) > 0.6 ? Double.random(in: 1...6, using: &rng) : 0),
            ]
            for (stage, minutes) in plan where minutes > 0.5 {
                let d = Swift.min(minutes * 60, end.timeIntervalSince(t))
                guard d > 0 else { break }
                if let last = out.last, last.stage == stage {
                    out[out.count - 1].duration += d
                } else {
                    out.append(SleepSegment(start: t, duration: d, stage: stage))
                }
                t = t.addingTimeInterval(d)
            }
            cycle += 1
        }
        return out
    }
}
