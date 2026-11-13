import SwiftUI

enum DetailRoute: Hashable {
    case recovery(Date), strain(Date), sleep(Date), stress(Date), journal(Date)
}

struct TodayView: View {
    @EnvironmentObject private var store: HealthStore
    @EnvironmentObject private var bluetooth: BluetoothManager
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())

    private var cal: Calendar { Calendar.current }
    private var score: DayScore? { store.score(for: selectedDay) }
    private var history: [DayScore] { store.history(before: selectedDay) }
    private var isToday: Bool { cal.isDateInToday(selectedDay) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let score, score.hasSleep || score.avgHR != nil {
                        let insights = store.coach.insights(today: score, history: history)
                        hero(score)
                        if let first = insights.first { CoachCard(insight: first, score: score) }
                        if isToday { TonightCard(plan: store.coach.bedtimePlan(today: score, history: history)) }
                        if isToday && store.journalDay(selectedDay) == nil { JournalPromptCard(day: selectedDay) }
                        VitalsGrid(score: score)
                        StressMiniCard(day: selectedDay)
                        if insights.count > 1 { InsightList(insights: Array(insights.dropFirst())) }
                        if !score.workouts.isEmpty { WorkoutsCard(workouts: score.workouts) }
                    } else {
                        EmptyDayCard(isToday: isToday)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .refreshable {
                bluetooth.sync()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                store.refreshIfNewDay()
            }
            .navigationDestination(for: DetailRoute.self) { route in
                switch route {
                case .recovery(let d): RecoveryDetailView(day: d)
                case .strain(let d): StrainDetailView(day: d)
                case .sleep(let d): SleepDetailView(day: d)
                case .stress(let d): StressView(day: d)
                case .journal(let d): JournalView(day: d)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday ? "Today" : selectedDay.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(selectedDay.formatted(.dateTime.month(.wide).day()))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    dayButton("chevron.left", by: -1, disabled: false)
                    dayButton("chevron.right", by: 1, disabled: isToday)
                }
            }
            SyncStatusChip()
        }
        .padding(.top, 8)
    }

    private func dayButton(_ symbol: String, by days: Int, disabled: Bool) -> some View {
        Button {
            if let d = cal.date(byAdding: .day, value: days, to: selectedDay) {
                withAnimation(.snappy) { selectedDay = d }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 38, height: 38)
                .background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke))
        }
        .foregroundStyle(disabled ? Theme.textTertiary : Theme.textPrimary)
        .disabled(disabled)
    }

    // MARK: Hero rings

    private func hero(_ s: DayScore) -> some View {
        Card(padding: 16) {
            HStack(alignment: .top) {
                NavigationLink(value: DetailRoute.recovery(s.day)) {
                    MetricRing(title: "Recovery",
                               value: s.recovery.map { "\(Int($0))" } ?? "—",
                               unit: s.recovery == nil ? nil : "%",
                               progress: (s.recovery ?? 0) / 100,
                               color: Theme.recovery(s.recovery),
                               caption: s.recovery.map { RecoveryZone($0).rawValue.capitalized } ?? "Calibrating")
                }
                Spacer(minLength: 4)
                NavigationLink(value: DetailRoute.strain(s.day)) {
                    MetricRing(title: "Strain",
                               value: String(format: "%.1f", s.strain),
                               unit: nil,
                               progress: s.strain / 21,
                               color: Theme.strain,
                               caption: "of 21")
                }
                Spacer(minLength: 4)
                NavigationLink(value: DetailRoute.sleep(s.day)) {
                    MetricRing(title: "Sleep",
                               value: s.sleepPerformance.map { "\(Int($0))" } ?? "—",
                               unit: s.sleepPerformance == nil ? nil : "%",
                               progress: (s.sleepPerformance ?? 0) / 100,
                               color: Theme.sleep,
                               caption: s.hasSleep ? Format.duration(s.asleep) : "No data")
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Journal prompt & stress

struct JournalPromptCard: View {
    var day: Date

    var body: some View {
        NavigationLink(value: DetailRoute.journal(day)) {
            HStack(spacing: 12) {
                Image(systemName: "book.closed.fill").font(.title3).foregroundStyle(Theme.strain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("How was yesterday?").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("Log your habits — 30 seconds — to learn what drives your recovery.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.strain.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}

struct StressMiniCard: View {
    var day: Date
    @EnvironmentObject private var store: HealthStore

    var body: some View {
        let summary = StressMonitor.summary(store.stressTimeline(for: day))
        if let summary {
            NavigationLink(value: DetailRoute.stress(day)) {
                Card {
                    SectionLabel(text: "Stress monitor", trailing: "0–3")
                    StressSummaryRow(summary: summary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Sync status

struct SyncStatusChip: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var store: HealthStore

    var body: some View {
        HStack(spacing: 6) {
            if bluetooth.isAnySyncing {
                ProgressView().controlSize(.mini).tint(Theme.strain)
                Text("Syncing your watch…")
            } else if let device = bluetooth.primaryDevice {
                Circle().fill(bluetooth.connected.contains(device.id) ? Theme.recoveryGreen : Theme.textTertiary)
                    .frame(width: 7, height: 7)
                Text(device.name)
                if let last = device.lastSync {
                    Text("· synced \(last.formatted(.relative(presentation: .named)))")
                }
                if let b = device.battery { Text("· \(b)%") }
            } else if store.hasDemoData {
                Image(systemName: "sparkles")
                Text("Showing demo data")
            } else {
                Image(systemName: "applewatch.slash")
                Text("No device connected")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
    }
}

// MARK: - Coach

struct CoachCard: View {
    var insight: Insight
    var score: DayScore

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insight.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.tone(insight.tone))
                    .frame(width: 40, height: 40)
                    .background(Theme.tone(insight.tone).opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(insight.title).font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(insight.message).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let rec = score.recovery {
                let target = RecoveryZone(rec).strainTarget
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Strain target").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("\(String(format: "%.1f", score.strain)) / \(Int(target.lowerBound))–\(Int(target.upperBound))")
                            .font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(Theme.strain)
                    }
                    RangeBar(value: score.strain, maxValue: 21, color: Theme.strain, target: target, height: 8)
                }
            }
        }
    }
}

struct InsightList: View {
    var insights: [Insight]

    var body: some View {
        Card {
            SectionLabel(text: "Feedback")
            ForEach(insights) { i in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: i.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.tone(i.tone))
                        .frame(width: 30, height: 30)
                        .background(Theme.tone(i.tone).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(i.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text(i.message).font(.footnote).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if i.id != insights.last?.id { Divider().overlay(Theme.stroke) }
            }
        }
    }
}

// MARK: - Tonight

struct TonightCard: View {
    var plan: Coach.BedtimePlan

    var body: some View {
        Card {
            SectionLabel(text: "Tonight", trailing: "Sleep planner")
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("In bed by").font(.caption).foregroundStyle(Theme.textSecondary)
                    Text(Format.clock(plan.bedtime)).font(.score(30)).foregroundStyle(Theme.sleep)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Sleep need").font(.caption).foregroundStyle(Theme.textSecondary)
                    Text(Format.duration(plan.need)).font(.score(22, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                }
            }
            HStack(spacing: 6) {
                chip("Baseline", plan.breakdown.baseline, sign: "")
                if plan.breakdown.strain >= 60 { chip("Strain", plan.breakdown.strain, sign: "+") }
                if plan.breakdown.debt >= 60 { chip("Debt", plan.breakdown.debt, sign: "+") }
                if plan.breakdown.naps >= 60 { chip("Naps", plan.breakdown.naps, sign: "−") }
            }
            Text("Wake around \(Format.clock(plan.wake)). Getting into bed on time is the single biggest lever on tomorrow's recovery.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
    }

    private func chip(_ label: String, _ t: TimeInterval, sign: String) -> some View {
        VStack(spacing: 2) {
            Text("\(sign)\(Format.duration(t))").font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
            Text(label).font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Vitals

struct VitalsGrid: View {
    var score: DayScore

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            VitalTile(title: "Resting HR", symbol: "heart.fill", color: Theme.recoveryRed,
                      value: score.restingHR.map { "\(Int($0.rounded()))" }, unit: "bpm",
                      delta: delta(score.restingHR, score.rhrBaseline?.mean), deltaUnit: "", goodWhenUp: false)
            if let hrv = score.hrv {
                VitalTile(title: "HRV", symbol: "waveform.path.ecg", color: Theme.recoveryGreen,
                          value: "\(Int(hrv.rounded()))", unit: "ms",
                          delta: score.hrvBaseline.map { hrv - exp($0.mean) }, deltaUnit: "", goodWhenUp: true)
            } else {
                VitalTile(title: "Night stress", symbol: "brain.head.profile", color: Theme.recoveryYellow,
                          value: score.overnightStress.map { "\(Int($0.rounded()))" }, unit: "/100",
                          delta: delta(score.overnightStress, score.stressBaseline?.mean), deltaUnit: "", goodWhenUp: false)
            }
            VitalTile(title: "Blood oxygen", symbol: "lungs.fill", color: Theme.stageREM,
                      value: score.spo2.map { String(format: "%.0f", $0) }, unit: "%",
                      delta: delta(score.spo2, score.spo2Baseline?.mean), deltaUnit: "", goodWhenUp: true, decimals: 1)
            VitalTile(title: "Steps", symbol: "figure.walk", color: Theme.strain,
                      value: score.steps > 0 ? score.steps.formatted() : nil, unit: nil,
                      delta: nil, deltaUnit: "", goodWhenUp: true,
                      footnote: score.activeCalories > 0 ? "\(score.activeCalories) kcal active" : nil)
        }
    }

    private func delta(_ v: Double?, _ base: Double?) -> Double? {
        guard let v, let base else { return nil }
        return v - base
    }
}

struct VitalTile: View {
    var title: String
    var symbol: String
    var color: Color
    var value: String?
    var unit: String?
    var delta: Double?
    var deltaUnit: String
    var goodWhenUp: Bool
    var decimals: Int = 0
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(color)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "—").font(.score(26)).foregroundStyle(Theme.textPrimary)
                if let unit, value != nil { Text(unit).font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary) }
            }
            if let delta {
                DeltaBadge(delta: delta, unit: deltaUnit, goodWhenUp: goodWhenUp, decimals: decimals)
            } else {
                Text(footnote ?? "Building baseline")
                    .font(.caption2.weight(.medium)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
    }
}

// MARK: - Workouts

struct WorkoutsCard: View {
    var workouts: [WorkoutScore]

    var body: some View {
        Card {
            SectionLabel(text: "Activities")
            ForEach(workouts) { w in
                HStack(spacing: 12) {
                    Text(String(format: "%.1f", w.strain))
                        .font(.score(16))
                        .foregroundStyle(Theme.strain)
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Theme.strain.opacity(0.5), lineWidth: 3))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.activity).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text("\(Format.clock(w.start)) · \(Format.duration(w.end.timeIntervalSince(w.start)))")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if let avg = w.avgHR {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(avg) bpm").font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Text("avg HR").font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Empty state

struct EmptyDayCard: View {
    var isToday: Bool
    @EnvironmentObject private var store: HealthStore
    @EnvironmentObject private var nav: Navigator

    var body: some View {
        Card(padding: 22) {
            Image(systemName: store.hasAnyData ? "moon.zzz" : "applewatch.radiowaves.left.and.right")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.strain)
            if store.hasAnyData {
                Text(isToday ? "Waiting for today's data" : "Nothing recorded this day")
                    .font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(isToday ? "Wear your watch to sleep and pull down to sync. Your scores appear after the first night."
                             : "Your watch wasn't worn or synced on this day.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            } else {
                Text("Your body, decoded")
                    .font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text("Connect a watch or heart-rate sensor and OpenPulse turns its raw data into daily Recovery, Strain and Sleep scores — with feedback on what to do next.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                Button {
                    nav.tab = .devices
                } label: {
                    Label("Connect a device", systemImage: "plus.circle.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.strain, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.black)
                }
                Button {
                    store.loadDemoData()
                } label: {
                    Text("Explore with demo data")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(Theme.textPrimary)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}
