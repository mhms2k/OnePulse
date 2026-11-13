import Foundation
import SwiftData
import SwiftUI

/// Detailed raw data for one day, used by the charts.
struct DayDetail {
    var day: Date
    var heartRate: [HRPoint] = []
    var sleep: SleepRecord?
    var stress: [ValuePoint] = []
    var spo2: [ValuePoint] = []
    var hrv: [ValuePoint] = []
}

/// Owns the database and the scoring pipeline: ingest → bucket by day → score → publish.
@MainActor
final class HealthStore: ObservableObject {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    @Published private(set) var scores: [DayScore] = []
    @Published private(set) var lastUpdated: Date?
    /// Journal answers keyed by start of day.
    @Published private(set) var journal: [Date: JournalDay] = [:]
    /// Logged strength sessions, newest first.
    @Published private(set) var strengthWorkouts: [StrengthWorkout] = []
    @Published var profile: UserProfile {
        didSet {
            guard profile != oldValue else { return }
            profile.save()
            if profile.maxHeartRate != oldValue.maxHeartRate || profile.sex != oldValue.sex
                || profile.baselineSleepHours != oldValue.baselineSleepHours {
                recomputeAll()
            }
        }
    }

    var engine: ScoreEngine { ScoreEngine(profile: profile) }
    var coach: Coach { Coach(engine: engine) }

    init(inMemory: Bool = false) {
        let schema = Schema(StoreSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // A corrupt store should never brick the app: fall back to memory and say so in the log.
            print("OpenPulse: failed to open store (\(error)); using in-memory store")
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        profile = UserProfile.load()
        loadScores()
        loadJournal()
        loadStrength()
        if scores.isEmpty || Calendar.current.isDateInToday(scores.last?.day ?? .distantPast) == false {
            recompute(from: scores.last?.day ?? Date())
        }
    }

    /// Adds empty days up to today (and re-scores today) after the app was in the background.
    func refreshIfNewDay() {
        recompute(from: scores.last?.day ?? Date())
    }

    func loadDemoData() {
        for (day, answers) in DemoData.journal() where journal[day] == nil {
            context.insert(JournalEntry(day: day, answers: answers, notes: "", source: DemoData.source))
        }
        for w in DemoData.strengthWorkouts() { context.insert(StrengthEntry(w)) }
        save()
        loadJournal()
        loadStrength()
        ingest(DemoData.generate())
    }

    var hasDemoData: Bool {
        var d = FetchDescriptor<SleepEntry>(predicate: #Predicate<SleepEntry> { $0.source == "Demo" })
        d.fetchLimit = 1
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }

    // MARK: Queries

    var today: DayScore? { scores.last }

    func score(for day: Date) -> DayScore? {
        let d = Calendar.current.startOfDay(for: day)
        return scores.last(where: { $0.day == d })
    }

    func history(before day: Date) -> [DayScore] {
        let d = Calendar.current.startOfDay(for: day)
        return scores.filter { $0.day < d }
    }

    var hasAnyData: Bool { scores.contains { $0.hasSleep || $0.avgHR != nil } }

    func detail(for day: Date) -> DayDetail {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        var d = DayDetail(day: start)
        d.heartRate = fetchHR(from: start, to: end)
        let sleeps = fetchSleep(from: start.addingTimeInterval(-36 * 3600), to: end)
        d.sleep = mainSleep(endingIn: start, end, from: sleeps)
        d.stress = fetchVitals(.stress, from: start, to: end)
        d.spo2 = fetchVitals(.spo2, from: start, to: end)
        d.hrv = fetchVitals(.hrv, from: start, to: end)
        return d
    }

    // MARK: Ingest

    func ingest(_ batch: HealthBatch) {
        guard !batch.isEmpty else { return }
        for p in batch.heartRate { context.insert(HeartRateEntry(date: p.date, bpm: p.bpm, source: batch.source)) }
        for p in batch.hrv { context.insert(VitalEntry(kind: .hrv, date: p.date, value: p.value, source: batch.source)) }
        for p in batch.spo2 { context.insert(VitalEntry(kind: .spo2, date: p.date, value: p.value, source: batch.source)) }
        for p in batch.stress { context.insert(VitalEntry(kind: .stress, date: p.date, value: p.value, source: batch.source)) }
        for p in batch.restingHeartRate { context.insert(VitalEntry(kind: .restingHR, date: p.date, value: p.value, source: batch.source)) }
        for p in batch.steps { context.insert(ActivityEntry(p, source: batch.source)) }
        for s in batch.sleep { context.insert(SleepEntry(s)) }
        for w in batch.workouts { context.insert(WorkoutEntry(w)) }
        save()

        var earliest = Date()
        func consider(_ d: Date?) { if let d, d < earliest { earliest = d } }
        consider(batch.heartRate.map(\.date).min())
        consider(batch.sleep.map(\.start).min())
        consider(batch.steps.map(\.date).min())
        consider(batch.stress.map(\.date).min())
        consider(batch.spo2.map(\.date).min())
        consider(batch.hrv.map(\.date).min())
        consider(batch.workouts.map(\.start).min())
        recompute(from: earliest)
    }

    func deleteAll(source: String? = nil) {
        do {
            if let source {
                try context.delete(model: HeartRateEntry.self, where: #Predicate<HeartRateEntry> { $0.source == source })
                try context.delete(model: VitalEntry.self, where: #Predicate<VitalEntry> { $0.source == source })
                try context.delete(model: ActivityEntry.self, where: #Predicate<ActivityEntry> { $0.source == source })
                try context.delete(model: SleepEntry.self, where: #Predicate<SleepEntry> { $0.source == source })
                try context.delete(model: WorkoutEntry.self, where: #Predicate<WorkoutEntry> { $0.source == source })
            } else {
                try context.delete(model: HeartRateEntry.self)
                try context.delete(model: VitalEntry.self)
                try context.delete(model: ActivityEntry.self)
                try context.delete(model: SleepEntry.self)
                try context.delete(model: WorkoutEntry.self)
            }
            try context.delete(model: DayScoreEntry.self)
            if let source {
                try context.delete(model: JournalEntry.self, where: #Predicate<JournalEntry> { $0.source == source })
                try context.delete(model: StrengthEntry.self, where: #Predicate<StrengthEntry> { $0.source == source })
            } else {
                try context.delete(model: JournalEntry.self)
                try context.delete(model: StrengthEntry.self)
            }
            save()
        } catch {
            print("OpenPulse: delete failed \(error)")
        }
        loadJournal()
        loadStrength()
        scores = []
        recomputeAll()
    }

    // MARK: Journal, strength, stress, healthspan

    var journalAnswers: [Date: [String: Bool]] { journal.mapValues(\.answers) }

    func journalDay(_ day: Date) -> JournalDay? { journal[Calendar.current.startOfDay(for: day)] }

    func saveJournal(day: Date, answers: [String: Bool], notes: String) {
        let d = Calendar.current.startOfDay(for: day)
        context.insert(JournalEntry(day: d, answers: answers, notes: notes, source: "User"))
        save()
        journal[d] = JournalDay(answers: answers, notes: notes, source: "User")
    }

    func saveStrength(_ workout: StrengthWorkout) {
        var w = workout
        if w.source == DemoData.source { w.source = "User" }
        context.insert(StrengthEntry(w))
        save()
        loadStrength()
    }

    func deleteStrength(_ workout: StrengthWorkout) {
        let id = workout.id
        do {
            try context.delete(model: StrengthEntry.self, where: #Predicate<StrengthEntry> { $0.uuid == id })
        } catch {
            print("OpenPulse: delete failed \(error)")
        }
        save()
        loadStrength()
    }

    var behaviorInsights: [BehaviorInsight] { BehaviorAnalyzer.insights(journal: journalAnswers, scores: scores) }

    var healthspan: HealthspanResult? {
        Healthspan.compute(scores: scores, strength: strengthWorkouts, profile: profile)
    }

    func stressTimeline(for day: Date) -> [StressSample] {
        let d = detail(for: day)
        let s = score(for: day)
        return StressMonitor.timeline(heartRate: d.heartRate, watchStress: d.stress,
                                      restingHR: s?.restingHR ?? s?.rhrBaseline?.mean,
                                      workouts: s?.workouts ?? [], sleep: d.sleep)
    }

    private func loadJournal() {
        let all = (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []
        var map: [Date: JournalDay] = [:]
        for e in all { map[e.day] = JournalDay(answers: e.answers, notes: e.notes, source: e.source) }
        journal = map
    }

    private func loadStrength() {
        let d = FetchDescriptor<StrengthEntry>(sortBy: [SortDescriptor(\.start, order: .reverse)])
        strengthWorkouts = ((try? context.fetch(d)) ?? []).compactMap(\.workout)
    }

    // MARK: Scoring pipeline

    func recomputeAll() {
        let earliest = [fetchEarliestHR(), fetchEarliestSleep()].compactMap { $0 }.min() ?? Date()
        recompute(from: earliest)
    }

    /// Re-scores every day from `date` through today. Days before `date` keep their
    /// cached scores and serve as the baseline history.
    func recompute(from date: Date) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var start = min(cal.startOfDay(for: date), todayStart)
        // Never score more than a year back in one go.
        start = max(start, cal.date(byAdding: .day, value: -365, to: todayStart) ?? start)
        let end = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        let history = scores.filter { $0.day < start }
        let inputs = buildInputs(from: start, to: end)
        let engine = self.engine
        var results = history
        for input in inputs {
            results.append(engine.score(input, history: results))
        }

        // Persist the re-scored days.
        let fresh = results.filter { $0.day >= start }
        for s in fresh { context.insert(DayScoreEntry(s)) }
        save()

        // Drop leading empty days so trends start at the first real data.
        if let firstReal = results.firstIndex(where: { $0.hasSleep || $0.avgHR != nil }) {
            scores = Array(results[firstReal...])
        } else {
            scores = results.filter { cal.isDateInToday($0.day) }
        }
        lastUpdated = Date()
    }

    private func buildInputs(from start: Date, to end: Date) -> [DayInput] {
        let cal = Calendar.current
        let hr = fetchHR(from: start.addingTimeInterval(-36 * 3600), to: end)
        let sleeps = fetchSleep(from: start.addingTimeInterval(-36 * 3600), to: end)
        let hrv = fetchVitals(.hrv, from: start.addingTimeInterval(-36 * 3600), to: end)
        let stress = fetchVitals(.stress, from: start.addingTimeInterval(-36 * 3600), to: end)
        let spo2 = fetchVitals(.spo2, from: start.addingTimeInterval(-36 * 3600), to: end)
        let rhr = fetchVitals(.restingHR, from: start, to: end)
        let activity = fetchActivity(from: start, to: end)
        let workouts = fetchWorkouts(from: start, to: end)

        var inputs: [DayInput] = []
        var day = start
        while day < end {
            let next = cal.date(byAdding: .day, value: 1, to: day) ?? end
            var input = DayInput(day: day)
            input.mainSleep = mainSleep(endingIn: day, next, from: sleeps)
            input.naps = sleeps.filter { $0.isNap && $0.start >= day && $0.start < next }
            input.heartRate = hr.filter { $0.date >= day && $0.date < next }
            if let s = input.mainSleep {
                input.sleepHeartRate = hr.filter { $0.date >= s.start && $0.date <= s.end }
                input.sleepHRV = hrv.filter { $0.date >= s.start && $0.date <= s.end }
                input.sleepStress = stress.filter { $0.date >= s.start && $0.date <= s.end }
                input.sleepSpO2 = spo2.filter { $0.date >= s.start && $0.date <= s.end }
            }
            input.reportedRestingHR = Stats.mean(rhr.filter { $0.date >= day && $0.date < next }.map(\.value))
            input.stress = stress.filter { $0.date >= day && $0.date < next }
            let dayActivity = activity.filter { $0.date >= day && $0.date < next }
            input.steps = dayActivity.reduce(0) { $0 + $1.steps }
            input.activeCalories = dayActivity.reduce(0) { $0 + $1.calories }
            input.workouts = workouts.filter { $0.start >= day && $0.start < next }
            inputs.append(input)
            day = next
        }
        return inputs
    }

    /// The longest non-nap sleep that ended within the day.
    private func mainSleep(endingIn start: Date, _ end: Date, from sleeps: [SleepRecord]) -> SleepRecord? {
        let candidates = sleeps.filter { $0.end >= start && $0.end < end && !$0.isNap }
        guard var best = candidates.max(by: { $0.timeInBed < $1.timeInBed }) else { return nil }
        // Merge fragments of the same night (watch split the session after a wake-up).
        for other in candidates where other != best {
            if other.end <= best.start, best.start.timeIntervalSince(other.end) < 90 * 60 {
                best = SleepRecord(start: other.start, end: best.end,
                                   segments: (other.segments + best.segments).sorted { $0.start < $1.start }, source: best.source)
            } else if other.start >= best.end, other.start.timeIntervalSince(best.end) < 90 * 60 {
                best = SleepRecord(start: best.start, end: other.end,
                                   segments: (best.segments + other.segments).sorted { $0.start < $1.start }, source: best.source)
            }
        }
        return best
    }

    // MARK: Fetch helpers

    private func fetchHR(from: Date, to: Date) -> [HRPoint] {
        let d = FetchDescriptor<HeartRateEntry>(predicate: #Predicate<HeartRateEntry> { $0.date >= from && $0.date < to },
                                                sortBy: [SortDescriptor(\.date)])
        return ((try? context.fetch(d)) ?? []).map { HRPoint(date: $0.date, bpm: $0.bpm) }
    }

    private func fetchVitals(_ kind: VitalKind, from: Date, to: Date) -> [ValuePoint] {
        let k = kind.rawValue
        let d = FetchDescriptor<VitalEntry>(predicate: #Predicate<VitalEntry> { $0.kind == k && $0.date >= from && $0.date < to },
                                            sortBy: [SortDescriptor(\.date)])
        return ((try? context.fetch(d)) ?? []).map { ValuePoint(date: $0.date, value: $0.value) }
    }

    private func fetchSleep(from: Date, to: Date) -> [SleepRecord] {
        let d = FetchDescriptor<SleepEntry>(predicate: #Predicate<SleepEntry> { $0.end >= from && $0.start < to },
                                            sortBy: [SortDescriptor(\.start)])
        return ((try? context.fetch(d)) ?? []).map(\.record)
    }

    private func fetchActivity(from: Date, to: Date) -> [StepPoint] {
        let d = FetchDescriptor<ActivityEntry>(predicate: #Predicate<ActivityEntry> { $0.date >= from && $0.date < to })
        return ((try? context.fetch(d)) ?? []).map {
            StepPoint(date: $0.date, steps: $0.steps, distance: $0.distance, calories: $0.calories)
        }
    }

    private func fetchWorkouts(from: Date, to: Date) -> [WorkoutRecord] {
        let d = FetchDescriptor<WorkoutEntry>(predicate: #Predicate<WorkoutEntry> { $0.start >= from && $0.start < to },
                                              sortBy: [SortDescriptor(\.start)])
        return ((try? context.fetch(d)) ?? []).map(\.record)
    }

    private func fetchEarliestHR() -> Date? {
        var d = FetchDescriptor<HeartRateEntry>(sortBy: [SortDescriptor(\.date)])
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.date
    }

    private func fetchEarliestSleep() -> Date? {
        var d = FetchDescriptor<SleepEntry>(sortBy: [SortDescriptor(\.start)])
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.start
    }

    private func loadScores() {
        let d = FetchDescriptor<DayScoreEntry>(sortBy: [SortDescriptor(\.day)])
        let all = ((try? context.fetch(d)) ?? []).compactMap(\.score)
        if let firstReal = all.firstIndex(where: { $0.hasSleep || $0.avgHR != nil }) {
            scores = Array(all[firstReal...])
        } else {
            scores = []
        }
    }

    private func save() {
        do { try context.save() } catch { print("OpenPulse: save failed \(error)") }
    }
}
