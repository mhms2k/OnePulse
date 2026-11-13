import Foundation

// Plain value types shared by device drivers, storage and the scoring engine.
// Keeping them free of SwiftData/UIKit makes the engine pure and easy to test.

enum SleepStage: Int, Codable, CaseIterable, Hashable {
    case awake = 0, light = 1, deep = 2, rem = 3

    var title: String {
        switch self {
        case .awake: return "Awake"
        case .light: return "Light"
        case .deep: return "Deep (SWS)"
        case .rem: return "REM"
        }
    }

    /// Display order on a hypnogram, top to bottom.
    var depth: Int {
        switch self {
        case .awake: return 0
        case .rem: return 1
        case .light: return 2
        case .deep: return 3
        }
    }
}

struct SleepSegment: Codable, Hashable {
    var start: Date
    var duration: TimeInterval
    var stage: SleepStage
    var end: Date { start.addingTimeInterval(duration) }
}

struct SleepRecord: Hashable {
    var start: Date
    var end: Date
    var segments: [SleepSegment]
    var source: String

    var timeInBed: TimeInterval { max(0, end.timeIntervalSince(start)) }

    func time(in stage: SleepStage) -> TimeInterval {
        let staged = segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
        if stage == .awake {
            // Any part of the session not covered by a stage counts as awake.
            let covered = segments.reduce(0) { $0 + $1.duration }
            return staged + max(0, timeInBed - covered)
        }
        return staged
    }

    var asleep: TimeInterval {
        if segments.isEmpty { return timeInBed }
        return time(in: .light) + time(in: .deep) + time(in: .rem)
    }

    /// Short daytime sleeps count as naps rather than the main night.
    var isNap: Bool {
        let hour = Calendar.current.component(.hour, from: start)
        return timeInBed < 3 * 3600 && (10...19).contains(hour)
    }
}

struct HRPoint: Hashable { var date: Date; var bpm: Int }
struct ValuePoint: Hashable { var date: Date; var value: Double }
struct StepPoint: Hashable { var date: Date; var steps: Int; var distance: Int; var calories: Int }

struct WorkoutRecord: Hashable {
    var start: Date
    var end: Date
    var activity: String
    var source: String
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// One batch of data produced by a device sync (or the demo generator).
struct HealthBatch {
    /// Device that produced the samples (sleep and workout records carry their own source).
    var source: String = "Wearable"
    var heartRate: [HRPoint] = []
    var restingHeartRate: [ValuePoint] = []
    var hrv: [ValuePoint] = []          // RMSSD in ms
    var spo2: [ValuePoint] = []
    var stress: [ValuePoint] = []
    var steps: [StepPoint] = []
    var sleep: [SleepRecord] = []
    var workouts: [WorkoutRecord] = []

    var isEmpty: Bool {
        heartRate.isEmpty && restingHeartRate.isEmpty && hrv.isEmpty && spo2.isEmpty &&
            stress.isEmpty && steps.isEmpty && sleep.isEmpty && workouts.isEmpty
    }

    var summary: String {
        var parts: [String] = []
        if !heartRate.isEmpty { parts.append("\(heartRate.count) heart rate") }
        if !hrv.isEmpty { parts.append("\(hrv.count) HRV") }
        if !sleep.isEmpty { parts.append("\(sleep.count) sleep") }
        if !spo2.isEmpty { parts.append("\(spo2.count) SpO₂") }
        if !stress.isEmpty { parts.append("\(stress.count) stress") }
        if !steps.isEmpty { parts.append("\(steps.count) activity") }
        if !workouts.isEmpty { parts.append("\(workouts.count) workouts") }
        return parts.isEmpty ? "No new data" : parts.joined(separator: ", ")
    }

    mutating func merge(_ other: HealthBatch) {
        heartRate += other.heartRate
        restingHeartRate += other.restingHeartRate
        hrv += other.hrv
        spo2 += other.spo2
        stress += other.stress
        steps += other.steps
        sleep += other.sleep
        workouts += other.workouts
    }
}
