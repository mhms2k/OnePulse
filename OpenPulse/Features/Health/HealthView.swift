import SwiftUI

/// Hub for the longer-term and lifestyle features: Healthspan, Stress, Journal,
/// Strength Trainer, Weekly Plan, Breathwork and cycle tracking.
struct HealthView: View {
    @EnvironmentObject private var store: HealthStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    healthspanCard
                    stressCard
                    WeeklyPlanCard()
                    journalCard
                    strengthCard
                    breathworkCard
                    if store.profile.sex == .female || !(store.profile.periodStarts ?? []).isEmpty {
                        CycleCard()
                    }
                    WeeklyReportCard()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Health")
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
    }

    // MARK: Cards

    private var healthspanCard: some View {
        NavigationLink {
            HealthspanView()
        } label: {
            Card {
                SectionLabel(text: "Healthspan", trailing: "Body age")
                if let h = store.healthspan {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", h.bodyAge)).font(.score(40)).foregroundStyle(Theme.textPrimary)
                        Text("years").font(.subheadline).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Pill(text: String(format: "%.1f× pace", h.paceOfAging), color: Theme.pace(h.paceOfAging), symbol: "speedometer")
                    }
                    Text(HealthspanView.differenceText(h))
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Your body age appears after about two weeks of data.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var stressCard: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let summary = StressMonitor.summary(store.stressTimeline(for: today))
        return NavigationLink {
            StressView(day: today)
        } label: {
            Card {
                SectionLabel(text: "Stress monitor", trailing: "today")
                if let summary {
                    StressSummaryRow(summary: summary)
                } else {
                    Text("Stress appears once your device has synced heart rate for today.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var journalCard: some View {
        let today = store.journalDay(Date())
        let insights = store.behaviorInsights
        return NavigationLink {
            JournalView()
        } label: {
            Card {
                SectionLabel(text: "Journal", trailing: today == nil ? "not logged today" : "logged today ✓")
                HStack(spacing: 12) {
                    Image(systemName: "book.closed.fill").font(.title2).foregroundStyle(Theme.strain)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(today == nil ? "How was yesterday?" : "Edit today's journal")
                            .font(.headline).foregroundStyle(Theme.textPrimary)
                        Text(insights.isEmpty
                             ? "Log your habits each morning to learn what helps your recovery."
                             : "\(insights.count) habit insight\(insights.count == 1 ? "" : "s") ready")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var strengthCard: some View {
        let week = StrengthStats.weeklyMinutes(store.strengthWorkouts, weeks: 1).last?.minutes ?? 0
        return NavigationLink {
            StrengthView()
        } label: {
            Card {
                SectionLabel(text: "Strength trainer", trailing: "\(Int(week)) min this week")
                HStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill").font(.title2).foregroundStyle(Theme.recoveryGreen)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Log sets, reps and weight").font(.headline).foregroundStyle(Theme.textPrimary)
                        Text("Volume, personal records and weekly strength time.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var breathworkCard: some View {
        NavigationLink {
            BreathworkView()
        } label: {
            Card {
                SectionLabel(text: "Breathwork")
                HStack(spacing: 12) {
                    Image(systemName: "wind").font(.title2).foregroundStyle(Theme.stageREM)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Relax, focus or wake up").font(.headline).foregroundStyle(Theme.textPrimary)
                        Text("Guided 1–5 minute breathing sessions.").font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Weekly plan

struct WeeklyPlanCard: View {
    @EnvironmentObject private var store: HealthStore
    @State private var editing = false

    var body: some View {
        let plan = store.profile.weeklyPlan
        let p = WeeklyReport.progress(scores: store.scores, strength: store.strengthWorkouts)
        Card {
            HStack {
                SectionLabel(text: "Weekly plan", trailing: "day \(p.daysElapsed) of 7")
                Button("Edit") { editing = true }
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.strain)
            }
            goalRow("Workouts", "\(p.workouts) / \(plan.workouts)",
                    Double(p.workouts) / Double(max(plan.workouts, 1)), Theme.strain)
            goalRow("Strength time", "\(Int(p.strengthMinutes)) / \(plan.strengthMinutes) min",
                    p.strengthMinutes / Double(max(plan.strengthMinutes, 1)), Theme.recoveryGreen)
            goalRow("Average sleep", String(format: "%.1f / %.1f h", p.sleepHours ?? 0, plan.sleepHours),
                    (p.sleepHours ?? 0) / max(plan.sleepHours, 1), Theme.sleep)
            goalRow("Average steps", "\(Int(p.dailySteps ?? 0).formatted()) / \(plan.dailySteps.formatted())",
                    (p.dailySteps ?? 0) / Double(max(plan.dailySteps, 1)), Theme.recoveryYellow)
        }
        .sheet(isPresented: $editing) { WeeklyPlanEditor() }
    }

    private func goalRow(_ label: String, _ value: String, _ fraction: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                if fraction >= 1 {
                    Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.recoveryGreen)
                }
                Text(value).font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
            }
            RangeBar(value: min(max(fraction, 0), 1), maxValue: 1, color: color, height: 7)
        }
    }
}

struct WeeklyPlanEditor: View {
    @EnvironmentObject private var store: HealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = WeeklyPlan()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Workouts  \(draft.workouts)", value: $draft.workouts, in: 0...14)
                    Stepper("Strength  \(draft.strengthMinutes) min", value: $draft.strengthMinutes, in: 0...600, step: 15)
                    Stepper("Sleep  \(String(format: "%.2f", draft.sleepHours)) h", value: $draft.sleepHours, in: 5...10, step: 0.25)
                    Stepper("Steps  \(draft.dailySteps.formatted()) a day", value: $draft.dailySteps, in: 1000...30000, step: 500)
                } footer: {
                    Text("Goals reset every week. Strength time counts logged sessions and strength workouts recorded by your watch.")
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Weekly plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.profile.plan = draft
                        dismiss()
                    }
                }
            }
            .onAppear { draft = store.profile.weeklyPlan }
        }
    }
}

// MARK: - Weekly report

struct WeeklyReportCard: View {
    @EnvironmentObject private var store: HealthStore

    var body: some View {
        let r = WeeklyReport.compare(scores: store.scores)
        Card {
            SectionLabel(text: "Weekly report", trailing: "last 7 days vs the 7 before")
            Grid(horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    cell("Recovery", r.current.recovery, r.previous.recovery, unit: "%", goodWhenUp: true)
                    cell("Strain", r.current.strain, r.previous.strain, unit: "", goodWhenUp: true, decimals: 1)
                }
                GridRow {
                    cell("Sleep", r.current.sleepHours, r.previous.sleepHours, unit: "h", goodWhenUp: true, decimals: 1)
                    cell("Resting HR", r.current.restingHR, r.previous.restingHR, unit: "", goodWhenUp: false)
                }
            }
        }
    }

    private func cell(_ label: String, _ now: Double?, _ before: Double?, unit: String,
                      goodWhenUp: Bool, decimals: Int = 0) -> some View {
        let format = "%.\(decimals)f"
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            Text(now.map { String(format: format, $0) + unit } ?? "—")
                .font(.score(20, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            if let now, let before {
                DeltaBadge(delta: now - before, unit: unit, goodWhenUp: goodWhenUp, decimals: decimals)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Cycle

struct CycleCard: View {
    @EnvironmentObject private var store: HealthStore

    var body: some View {
        let starts = store.profile.periodStarts ?? []
        let status = CycleTracker.status(periodStarts: starts)
        Card {
            SectionLabel(text: "Menstrual cycle", trailing: status.map { "day \($0.day) of ~\($0.length)" })
            if let s = status {
                HStack {
                    Pill(text: s.phase.rawValue + " phase", color: Theme.sleep, symbol: "circle.dotted")
                    Spacer()
                    Text("Next period ~\(s.nextPeriod.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
                }
                Text(s.guidance).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Log the first day of your period to see which phase you're in and how it affects recovery.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 10) {
                Button {
                    logToday()
                } label: {
                    Label("Period started today", systemImage: "drop.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Theme.textPrimary)
                }
                if !starts.isEmpty {
                    Button {
                        undoLast()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .frame(width: 44, height: 40)
                            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private func logToday() {
        var list = store.profile.periodStarts ?? []
        let today = Calendar.current.startOfDay(for: Date())
        if !list.contains(today) { list.append(today) }
        store.profile.periodStarts = list
    }

    private func undoLast() {
        var list = (store.profile.periodStarts ?? []).sorted()
        if !list.isEmpty { list.removeLast() }
        store.profile.periodStarts = list
    }
}
