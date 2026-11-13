import Foundation

/// Everything recorded for one calendar day, gathered by the data store.
struct DayInput {
    var day: Date                       // start of the calendar day
    var mainSleep: SleepRecord?         // the main sleep that ended on this day
    var naps: [SleepRecord] = []        // naps taken during this day
    var heartRate: [HRPoint] = []       // whole calendar day (strain)
    var sleepHeartRate: [HRPoint] = []  // inside the main sleep window
    var sleepHRV: [ValuePoint] = []
    var sleepStress: [ValuePoint] = []
    var sleepSpO2: [ValuePoint] = []
    var reportedRestingHR: Double?
    var stress: [ValuePoint] = []       // whole day
    var steps: Int = 0
    var activeCalories: Int = 0
    var workouts: [WorkoutRecord] = []
}

struct WorkoutScore: Codable, Hashable, Identifiable {
    var id: Date { start }
    var start: Date
    var end: Date
    var activity: String
    var strain: Double
    var avgHR: Int?
    var maxHR: Int?
}

/// The computed result for one day. Persisted so trends render instantly.
struct DayScore: Codable, Hashable, Identifiable {
    var id: Date { day }
    var day: Date

    // Overnight vitals
    var restingHR: Double?
    var hrv: Double?
    var overnightStress: Double?
    var spo2: Double?

    // Sleep
    var bedtime: Date?
    var wakeTime: Date?
    var timeInBed: TimeInterval = 0
    var asleep: TimeInterval = 0
    var light: TimeInterval = 0
    var deep: TimeInterval = 0
    var rem: TimeInterval = 0
    var awake: TimeInterval = 0
    var napTime: TimeInterval = 0
    var sleepNeed: TimeInterval = 0
    var sleepNeedBaseline: TimeInterval = 0
    var sleepNeedFromStrain: TimeInterval = 0
    var sleepNeedFromDebt: TimeInterval = 0
    var sleepNeedFromNaps: TimeInterval = 0
    var sleepPerformance: Double?
    var efficiency: Double?
    var consistency: Double?

    // Strain
    var strain: Double = 0
    var trimp: Double = 0
    var zoneMinutes: [Double] = [0, 0, 0, 0, 0]
    var avgHR: Int?
    var maxHR: Int?
    var steps: Int = 0
    var activeCalories: Int = 0
    var workouts: [WorkoutScore] = []

    // Recovery
    var recovery: Double?
    var isCalibrating: Bool = true
    var nightsUntilCalibrated: Int = 4

    // Baselines on that day (for "vs normal" comparisons)
    var rhrBaseline: Baseline?
    var hrvBaseline: Baseline?
    var stressBaseline: Baseline?
    var spo2Baseline: Baseline?

    var hasSleep: Bool { timeInBed > 0 }
    var restorative: TimeInterval { deep + rem }
}

enum RecoveryZone: String {
    case green, yellow, red

    init(_ score: Double) {
        if score >= 67 { self = .green } else if score >= 34 { self = .yellow } else { self = .red }
    }

    /// Optimal strain range for the day, WHOOP-style.
    var strainTarget: ClosedRange<Double> {
        switch self {
        case .green: return 14...18
        case .yellow: return 10...14
        case .red: return 4...10
        }
    }

    var title: String {
        switch self {
        case .green: return "Ready to perform"
        case .yellow: return "Maintain"
        case .red: return "Prioritize rest"
        }
    }
}

/// Turns raw days into Recovery, Strain and Sleep scores.
///
/// The model follows WHOOP's published principles:
/// * Recovery is driven mostly by the autonomic signal (HRV, or the watch's stress
///   index when beat-to-beat data is unavailable), then resting heart rate, sleep
///   performance and blood oxygen — each judged against *your own* 30-day baseline.
/// * Strain accumulates cardiovascular load (Banister TRIMP on heart-rate reserve)
///   on a logarithmic 0–21 scale.
/// * Sleep need = baseline + extra for yesterday's strain + sleep debt − naps.
struct ScoreEngine {
    var profile: UserProfile
    static let baselineDays = 30
    static let minNightsForRecovery = 4

    // MARK: Public

    /// Scores days in chronological order; each day only sees the days before it.
    func score(days inputs: [DayInput]) -> [DayScore] {
        var results: [DayScore] = []
        for input in inputs.sorted(by: { $0.day < $1.day }) {
            results.append(score(input, history: results))
        }
        return results
    }

    func score(_ input: DayInput, history: [DayScore]) -> DayScore {
        let recent = Array(history.suffix(Self.baselineDays))
        var s = DayScore(day: input.day)

        // --- Sleep ---------------------------------------------------------
        if let sleep = input.mainSleep {
            s.bedtime = sleep.start
            s.wakeTime = sleep.end
            s.timeInBed = sleep.timeInBed
            s.asleep = sleep.asleep
            s.light = sleep.time(in: .light)
            s.deep = sleep.time(in: .deep)
            s.rem = sleep.time(in: .rem)
            s.awake = sleep.time(in: .awake)
            if s.timeInBed > 0 { s.efficiency = Stats.clamp(s.asleep / s.timeInBed * 100, 0, 100) }
        }
        s.napTime = input.naps.reduce(0) { $0 + $1.asleep }

        let need = sleepNeed(history: recent)
        s.sleepNeedBaseline = need.baseline
        s.sleepNeedFromStrain = need.strain
        s.sleepNeedFromDebt = need.debt
        s.sleepNeedFromNaps = need.naps
        s.sleepNeed = need.total
        if s.hasSleep, s.sleepNeed > 0 {
            s.sleepPerformance = Stats.clamp(s.asleep / s.sleepNeed * 100, 0, 100)
        }
        s.consistency = consistency(current: s, history: recent)

        // --- Overnight vitals ------------------------------------------------
        s.restingHR = restingHeartRate(input)
        s.hrv = Stats.median(input.sleepHRV.map(\.value))
        s.overnightStress = Stats.mean(input.sleepStress.map(\.value))
        s.spo2 = Stats.mean(input.sleepSpO2.map(\.value))

        // --- Strain ----------------------------------------------------------
        let rhrForStrain = s.restingHR ?? Stats.mean(recent.compactMap(\.restingHR)) ?? 60
        let strain = strainLoad(input.heartRate, restingHR: rhrForStrain)
        s.trimp = strain.trimp
        s.strain = Self.strain(fromTRIMP: strain.trimp)
        s.zoneMinutes = strain.zoneMinutes
        let bpms = input.heartRate.map(\.bpm)
        if !bpms.isEmpty {
            s.avgHR = bpms.reduce(0, +) / bpms.count
            s.maxHR = bpms.max()
        }
        s.steps = input.steps
        s.activeCalories = input.activeCalories
        s.workouts = input.workouts.map { w in
            let hr = input.heartRate.filter { $0.date >= w.start && $0.date <= w.end }
            let load = strainLoad(hr, restingHR: rhrForStrain)
            let wb = hr.map(\.bpm)
            return WorkoutScore(start: w.start, end: w.end, activity: w.activity,
                                strain: Self.strain(fromTRIMP: load.trimp),
                                avgHR: wb.isEmpty ? nil : wb.reduce(0, +) / wb.count, maxHR: wb.max())
        }

        // --- Baselines + Recovery -------------------------------------------
        s.rhrBaseline = Baseline(recent.compactMap(\.restingHR), sdFloor: 1.5)
        s.hrvBaseline = Baseline(recent.compactMap(\.hrv).filter { $0 > 0 }.map { log($0) }, sdFloor: 0.08)
        s.stressBaseline = Baseline(recent.compactMap(\.overnightStress), sdFloor: 3)
        s.spo2Baseline = Baseline(recent.compactMap(\.spo2), sdFloor: 0.7)

        let nights = recent.filter { $0.restingHR != nil }.count
        s.nightsUntilCalibrated = max(0, Self.minNightsForRecovery - nights)
        s.recovery = recovery(for: s)
        s.isCalibrating = s.recovery == nil
        return s
    }

    // MARK: Recovery

    struct Contributor: Identifiable {
        enum Effect { case positive, neutral, negative }
        var id: String { name }
        var name: String
        var value: String
        var detail: String
        var z: Double
        var weight: Double
        var effect: Effect
    }

    /// The weighted, baseline-relative inputs behind a recovery score.
    func contributors(for s: DayScore) -> [Contributor] {
        var out: [Contributor] = []
        func effect(_ z: Double) -> Contributor.Effect { z > 0.5 ? .positive : (z < -0.5 ? .negative : .neutral) }

        if let hrv = s.hrv, hrv > 0, let b = s.hrvBaseline {
            let z = Stats.clamp(b.z(log(hrv)), -3, 3)
            out.append(Contributor(name: "Heart rate variability", value: "\(Int(hrv.rounded())) ms",
                                   detail: "Normal \(Int(exp(b.mean).rounded())) ms", z: z, weight: 0.5, effect: effect(z)))
        } else if let st = s.overnightStress, let b = s.stressBaseline {
            let z = Stats.clamp(-b.z(st), -3, 3)
            out.append(Contributor(name: "Overnight stress (HRV proxy)", value: "\(Int(st.rounded()))",
                                   detail: "Normal \(Int(b.mean.rounded()))", z: z, weight: 0.5, effect: effect(z)))
        }
        if let rhr = s.restingHR, let b = s.rhrBaseline {
            let z = Stats.clamp(-b.z(rhr), -3, 3)
            out.append(Contributor(name: "Resting heart rate", value: "\(Int(rhr.rounded())) bpm",
                                   detail: "Normal \(Int(b.mean.rounded())) bpm", z: z, weight: 0.3, effect: effect(z)))
        }
        if let perf = s.sleepPerformance {
            let z = Stats.clamp((perf - 80) / 15, -3, 1.5)
            out.append(Contributor(name: "Sleep performance", value: "\(Int(perf.rounded()))%",
                                   detail: "of \(Format.duration(s.sleepNeed)) needed", z: z, weight: 0.2, effect: effect(z)))
        }
        if let spo2 = s.spo2, let b = s.spo2Baseline {
            let z = Stats.clamp(min(0, b.z(spo2)), -3, 0)
            out.append(Contributor(name: "Blood oxygen", value: String(format: "%.1f%%", spo2),
                                   detail: String(format: "Normal %.1f%%", b.mean), z: z, weight: 0.1,
                                   effect: z < -0.5 ? .negative : .neutral))
        }
        return out
    }

    private func recovery(for s: DayScore) -> Double? {
        let c = contributors(for: s)
        // Need at least one calibrated physiological signal, not just sleep.
        guard c.contains(where: { $0.name != "Sleep performance" }) else { return nil }
        let totalWeight = c.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let composite = c.reduce(0) { $0 + $1.z * $1.weight } / totalWeight
        let score = 100 * Stats.logistic(1.4 * composite + 0.55)
        return Stats.clamp(score.rounded(), 1, 99)
    }

    private func restingHeartRate(_ input: DayInput) -> Double? {
        let sleepBpm = input.sleepHeartRate.map { Double($0.bpm) }
        if sleepBpm.count >= 6 {
            let q = Stats.percentile(sleepBpm, 0.25) ?? 0
            return Stats.mean(sleepBpm.filter { $0 <= q })
        }
        if let reported = input.reportedRestingHR { return reported }
        if sleepBpm.count >= 2 { return sleepBpm.min() }
        return nil
    }

    // MARK: Strain

    struct StrainLoad { var trimp: Double; var zoneMinutes: [Double] }

    /// Banister TRIMP over heart-rate reserve. Each sample stands for the time until the
    /// next one (capped at 10 minutes, so sparse all-day sampling is not over-counted).
    func strainLoad(_ samples: [HRPoint], restingHR: Double) -> StrainLoad {
        let sorted = samples.sorted { $0.date < $1.date }
        let maxHR = Double(profile.maxHeartRate)
        let reserve = max(20, maxHR - restingHR)
        let (a, b) = profile.sex == .female ? (0.86, 1.67) : (0.64, 1.92)
        var trimp = 0.0
        var zones = [Double](repeating: 0, count: 5)

        for (i, p) in sorted.enumerated() {
            let next = i + 1 < sorted.count ? sorted[i + 1].date : p.date.addingTimeInterval(60)
            let minutes = min(next.timeIntervalSince(p.date), 600) / 60
            guard minutes > 0 else { continue }
            let pctMax = Double(p.bpm) / maxHR
            if pctMax >= 0.5 { zones[min(4, Int((pctMax - 0.5) / 0.1))] += minutes }
            let hrr = Stats.clamp((Double(p.bpm) - restingHR) / reserve, 0, 1)
            guard hrr >= 0.25 else { continue } // resting/sedentary heart rate adds no strain
            trimp += minutes * hrr * a * exp(b * hrr)
        }
        return StrainLoad(trimp: trimp, zoneMinutes: zones)
    }

    /// Logarithmic 0–21 scale: easy to build early, very hard to approach 21.
    static func strain(fromTRIMP t: Double) -> Double {
        let v = 21 * (1 - exp(-t / 150))
        return (v * 10).rounded() / 10
    }

    // MARK: Sleep need

    struct SleepNeed { var baseline: TimeInterval; var strain: TimeInterval; var debt: TimeInterval; var naps: TimeInterval
        var total: TimeInterval { max(baseline * 0.75, baseline + strain + debt - naps) }
    }

    /// Need for the night that ends on the day being scored.
    func sleepNeed(history: [DayScore]) -> SleepNeed {
        let base = profile.baselineSleepHours * 3600
        guard let yesterday = history.last else { return SleepNeed(baseline: base, strain: 0, debt: 0, naps: 0) }
        return sleepNeed(after: yesterday, priorNights: Array(history.dropLast()))
    }

    /// Need for the night after `day` (e.g. tonight's need, using today's strain so far).
    func sleepNeed(after day: DayScore, priorNights: [DayScore]) -> SleepNeed {
        let base = profile.baselineSleepHours * 3600
        let strainExtra = max(0, day.strain - 8) / 13 * 50 * 60
        // Shortfall of recent nights, most recent weighted highest.
        let nights = (priorNights + [day]).suffix(3).reversed()
        var debt = 0.0
        for (i, n) in nights.enumerated() where n.hasSleep {
            // Measured against baseline + strain only, so debt doesn't compound night after night.
            let shortfall = max(0, n.sleepNeedBaseline + n.sleepNeedFromStrain - n.asleep)
            debt += shortfall * [0.5, 0.25, 0.125][i]
        }
        return SleepNeed(baseline: base, strain: strainExtra, debt: min(debt, 3 * 3600), naps: day.napTime)
    }

    /// 0–100 from how much bed and wake times varied over the last 4 nights.
    private func consistency(current: DayScore, history: [DayScore]) -> Double? {
        let nights = (history + [current]).filter(\.hasSleep).suffix(4)
        guard nights.count >= 2 else { return nil }
        func minutes(_ d: Date?) -> Double? {
            guard let d else { return nil }
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            if m < 12 * 60 { m += 24 * 60 } // measure around noon so 23:30 and 00:30 are close
            return m
        }
        let beds = nights.compactMap { minutes($0.bedtime) }
        let wakes = nights.compactMap { minutes($0.wakeTime) }
        guard let bm = Stats.mean(beds), let wm = Stats.mean(wakes) else { return nil }
        let dev = (beds.map { abs($0 - bm) } + wakes.map { abs($0 - wm) })
        let avgDev = Stats.mean(dev) ?? 0
        return Stats.clamp(100 - avgDev * 0.8, 0, 100).rounded()
    }

    /// Median wake time over the last week, or the profile default.
    func typicalWakeMinutes(history: [DayScore]) -> Int {
        let wakes = history.suffix(7).compactMap(\.wakeTime).map { d -> Double in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        guard wakes.count >= 3, let m = Stats.median(wakes) else { return profile.wakeMinutes }
        return Int(m)
    }
}

enum Format {
    static func duration(_ t: TimeInterval) -> String {
        let total = Int((t / 60).rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func clock(_ d: Date?) -> String {
        guard let d else { return "--" }
        return d.formatted(date: .omitted, time: .shortened)
    }

    static func clock(minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        var c = DateComponents()
        c.hour = m / 60
        c.minute = m % 60
        let d = Calendar.current.date(from: c) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }
}
