import Foundation
import SwiftData

// On-device storage. Every record has a deterministic `key` so re-syncing the
// same data from a watch never creates duplicates (SwiftData upserts on unique keys).

@Model
final class HeartRateEntry {
    @Attribute(.unique) var key: String
    var date: Date
    var bpm: Int
    var source: String

    init(date: Date, bpm: Int, source: String) {
        self.key = "\(source)|\(Int(date.timeIntervalSince1970))"
        self.date = date
        self.bpm = bpm
        self.source = source
    }
}

enum VitalKind: String, CaseIterable {
    case hrv, spo2, stress, restingHR
}

@Model
final class VitalEntry {
    @Attribute(.unique) var key: String
    var kind: String
    var date: Date
    var value: Double
    var source: String

    init(kind: VitalKind, date: Date, value: Double, source: String) {
        self.key = "\(kind.rawValue)|\(source)|\(Int(date.timeIntervalSince1970))"
        self.kind = kind.rawValue
        self.date = date
        self.value = value
        self.source = source
    }
}

@Model
final class ActivityEntry {
    @Attribute(.unique) var key: String
    var date: Date
    var steps: Int
    var distance: Int
    var calories: Int
    var source: String

    init(_ p: StepPoint, source: String) {
        self.key = "\(source)|\(Int(p.date.timeIntervalSince1970))"
        self.date = p.date
        self.steps = p.steps
        self.distance = p.distance
        self.calories = p.calories
        self.source = source
    }
}

@Model
final class SleepEntry {
    @Attribute(.unique) var key: String
    var start: Date
    var end: Date
    var source: String
    var segmentsData: Data

    init(_ r: SleepRecord) {
        self.key = "\(r.source)|\(Int(r.start.timeIntervalSince1970))"
        self.start = r.start
        self.end = r.end
        self.source = r.source
        self.segmentsData = (try? JSONEncoder().encode(r.segments)) ?? Data()
    }

    var record: SleepRecord {
        let segs = (try? JSONDecoder().decode([SleepSegment].self, from: segmentsData)) ?? []
        return SleepRecord(start: start, end: end, segments: segs, source: source)
    }
}

@Model
final class WorkoutEntry {
    @Attribute(.unique) var key: String
    var start: Date
    var end: Date
    var activity: String
    var source: String

    init(_ w: WorkoutRecord) {
        self.key = "\(w.source)|\(Int(w.start.timeIntervalSince1970))"
        self.start = w.start
        self.end = w.end
        self.activity = w.activity
        self.source = w.source
    }

    var record: WorkoutRecord { WorkoutRecord(start: start, end: end, activity: activity, source: source) }
}

/// Cached daily result so the dashboard and trends render instantly.
@Model
final class DayScoreEntry {
    @Attribute(.unique) var day: Date
    var payload: Data

    init(_ s: DayScore) {
        self.day = s.day
        self.payload = (try? JSONEncoder().encode(s)) ?? Data()
    }

    var score: DayScore? { try? JSONDecoder().decode(DayScore.self, from: payload) }
}

/// One morning's journal (answers are about the day before).
@Model
final class JournalEntry {
    @Attribute(.unique) var day: Date
    var answersData: Data
    var notes: String
    var source: String

    init(day: Date, answers: [String: Bool], notes: String, source: String) {
        self.day = day
        self.answersData = (try? JSONEncoder().encode(answers)) ?? Data()
        self.notes = notes
        self.source = source
    }

    var answers: [String: Bool] { (try? JSONDecoder().decode([String: Bool].self, from: answersData)) ?? [:] }
}

/// A logged strength-training session.
@Model
final class StrengthEntry {
    @Attribute(.unique) var uuid: UUID
    var start: Date
    var source: String
    var payload: Data

    init(_ w: StrengthWorkout) {
        self.uuid = w.id
        self.start = w.start
        self.source = w.source
        self.payload = (try? JSONEncoder().encode(w)) ?? Data()
    }

    var workout: StrengthWorkout? { try? JSONDecoder().decode(StrengthWorkout.self, from: payload) }
}

enum StoreSchema {
    static let models: [any PersistentModel.Type] = [
        HeartRateEntry.self, VitalEntry.self, ActivityEntry.self,
        SleepEntry.self, WorkoutEntry.self, DayScoreEntry.self,
        JournalEntry.self, StrengthEntry.self,
    ]
}
