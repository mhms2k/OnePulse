import SwiftUI

struct JournalView: View {
    @EnvironmentObject private var store: HealthStore
    @State private var day: Date
    @State private var answers: [String: Bool] = [:]
    @State private var notes = ""
    @State private var editingBehaviors = false
    @State private var saved = false

    init(day: Date = Date()) {
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
    }

    private var tracked: [Behavior] { store.profile.tracked.compactMap { Behavior.find($0) } }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        DetailScaffold(title: "Journal") {
            Card {
                HStack {
                    dayButton("chevron.left", by: -1, disabled: false)
                    Spacer()
                    VStack(spacing: 2) {
                        Text(isToday ? "This morning" : day.formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.headline).foregroundStyle(Theme.textPrimary)
                        Text("Answer about the day before").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    dayButton("chevron.right", by: 1, disabled: isToday)
                }
            }

            Card {
                SectionLabel(text: "Yesterday, did you…")
                if tracked.isEmpty {
                    Text("You're not tracking any behaviors yet.").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                ForEach(tracked) { b in
                    BehaviorRow(behavior: b, answer: binding(for: b.id))
                    if b.id != tracked.last?.id { Divider().overlay(Theme.stroke) }
                }
                Button {
                    editingBehaviors = true
                } label: {
                    Label("Choose what to track", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.strain)
                }
            }

            Card {
                SectionLabel(text: "Notes")
                TextField("Anything else worth remembering?", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                    .foregroundStyle(Theme.textPrimary)
            }

            Button {
                store.saveJournal(day: day, answers: answers, notes: notes)
                saved = true
            } label: {
                Label(saved ? "Saved" : "Save journal", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(saved ? Theme.cardRaised : Theme.strain, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(saved ? Theme.textPrimary : Color.black)
            }

            NavigationLink {
                BehaviorInsightsView()
            } label: {
                HStack {
                    Label("How your habits affect recovery", systemImage: "chart.bar.xaxis")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .onAppear { load() }
        .onChange(of: day) { _, _ in load() }
        .sheet(isPresented: $editingBehaviors) { BehaviorPickerView() }
    }

    private func dayButton(_ symbol: String, by days: Int, disabled: Bool) -> some View {
        Button {
            if let d = Calendar.current.date(byAdding: .day, value: days, to: day) { day = d }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .background(Theme.cardRaised, in: Circle())
        }
        .foregroundStyle(disabled ? Theme.textTertiary : Theme.textPrimary)
        .disabled(disabled)
    }

    private func binding(for id: String) -> Binding<Bool?> {
        Binding(get: { answers[id] }, set: { newValue in
            answers[id] = newValue
            saved = false
        })
    }

    private func load() {
        let entry = store.journalDay(day)
        answers = entry?.answers ?? [:]
        notes = entry?.notes ?? ""
        saved = entry != nil
    }
}

struct BehaviorRow: View {
    var behavior: Behavior
    @Binding var answer: Bool?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: behavior.symbol).foregroundStyle(Theme.strain).frame(width: 26)
            Text(behavior.question).font(.subheadline).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            choice("No", value: false)
            choice("Yes", value: true)
        }
    }

    private func choice(_ title: String, value: Bool) -> some View {
        let selected = answer == value
        return Button {
            answer = selected ? nil : value
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .frame(width: 44, height: 30)
                .background(selected ? (value ? Theme.strain : Theme.textSecondary) : Theme.cardRaised,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .foregroundStyle(selected ? Color.black : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

struct BehaviorPickerView: View {
    @EnvironmentObject private var store: HealthStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Behavior.Category.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(Behavior.catalog.filter { $0.category == category }) { b in
                            Button {
                                toggle(b.id)
                            } label: {
                                HStack {
                                    Label(b.title, systemImage: b.symbol).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    if store.profile.tracked.contains(b.id) {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.strain)
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Track behaviors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func toggle(_ id: String) {
        var list = store.profile.tracked
        if let i = list.firstIndex(of: id) { list.remove(at: i) } else { list.append(id) }
        store.profile.trackedBehaviors = list
    }
}

struct BehaviorInsightsView: View {
    @EnvironmentObject private var store: HealthStore

    var body: some View {
        let insights = store.behaviorInsights
        let journal = store.journalAnswers
        let counts = BehaviorAnalyzer.counts(journal: journal, scores: store.scores)
        let tracked = store.profile.tracked.compactMap { Behavior.find($0) }
        let pending = tracked.filter { b in !insights.contains { $0.behavior.id == b.id } }

        DetailScaffold(title: "Behavior insights") {
            Card {
                SectionLabel(text: "Impact on recovery")
                if insights.isEmpty {
                    Text("Insights unlock once a habit has at least 5 \"yes\" and 5 \"no\" answers on days with a Recovery score, within the last 90 days.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                ForEach(insights) { i in
                    InsightImpactRow(insight: i)
                    if i.id != insights.last?.id { Divider().overlay(Theme.stroke) }
                }
            }

            if !pending.isEmpty {
                Card {
                    SectionLabel(text: "Still learning")
                    ForEach(pending) { b in
                        let c = counts[b.id] ?? (yes: 0, no: 0)
                        HStack {
                            Label(b.title, systemImage: b.symbol).font(.subheadline).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(min(c.yes, 5))/5 yes · \(min(c.no, 5))/5 no")
                                .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }

            Card {
                SectionLabel(text: "Last 5 weeks", trailing: "■ yes  ■ no")
                ForEach(tracked) { b in
                    HabitStrip(behavior: b, journal: journal)
                }
            }

            Card {
                Text("These are associations in your own data, not proof of cause. Other things can happen on the same days — use them as clues to experiment with.")
                    .font(.footnote).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

struct InsightImpactRow: View {
    var insight: BehaviorInsight

    var body: some View {
        let up = insight.impact >= 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(insight.behavior.title, systemImage: insight.behavior.symbol)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(up ? "+" : "−")\(Int(abs(insight.impact).rounded()))% recovery")
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .foregroundStyle(up ? Theme.recoveryGreen : Theme.recoveryRed)
            }
            ImpactBar(z: insight.impact / 10)
            Text("Recovery averaged \(Int(insight.recoveryWithYes.rounded()))% after \"yes\" (\(insight.yesCount) days) vs \(Int(insight.recoveryWithNo.rounded()))% after \"no\" (\(insight.noCount) days).")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct HabitStrip: View {
    var behavior: Behavior
    var journal: [Date: [String: Bool]]

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days: [Date] = (0..<35).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let yesCount = days.filter { journal[$0]?[behavior.id] == true }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: behavior.symbol).font(.caption).foregroundStyle(Theme.strain)
                Text(behavior.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(yesCount) yes").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            HStack(spacing: 2) {
                ForEach(days, id: \.self) { d in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(journal[d]?[behavior.id]))
                        .frame(height: 14)
                }
            }
        }
    }

    private func color(_ answer: Bool?) -> Color {
        guard let answer else { return Theme.track }
        return answer ? Theme.strain : Theme.textTertiary
    }
}
