import SwiftUI
import Charts

struct StrengthView: View {
    @EnvironmentObject private var store: HealthStore
    @State private var editing: StrengthWorkout?

    var body: some View {
        DetailScaffold(title: "Strength trainer") {
            Button {
                editing = StrengthWorkout.new()
            } label: {
                Label("Log a strength session", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.recoveryGreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(Color.black)
            }
            weeklyCard
            recordsCard
            Card {
                SectionLabel(text: "Sessions", trailing: "\(store.strengthWorkouts.count)")
                if store.strengthWorkouts.isEmpty {
                    Text("No sessions yet. Log your sets, reps and weights after each workout.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                ForEach(store.strengthWorkouts) { w in
                    Button {
                        editing = w
                    } label: {
                        StrengthSessionRow(workout: w)
                    }
                    .buttonStyle(.plain)
                    if w.id != store.strengthWorkouts.last?.id { Divider().overlay(Theme.stroke) }
                }
            }
        }
        .sheet(item: $editing) { w in StrengthEditorView(workout: w) }
    }

    private var weeklyCard: some View {
        let weeks = StrengthStats.weeklyMinutes(store.strengthWorkouts, weeks: 8)
        let goal = Double(store.profile.weeklyPlan.strengthMinutes)
        return Card {
            SectionLabel(text: "Strength activity time", trailing: "goal \(Int(goal)) min/week")
            Chart {
                ForEach(weeks) { w in
                    BarMark(x: .value("Week", w.start, unit: .weekOfYear), y: .value("Minutes", w.minutes))
                        .foregroundStyle(Theme.recoveryGreen.gradient)
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 140)
        }
    }

    private var recordsCard: some View {
        let records = Array(StrengthStats.records(store.strengthWorkouts).prefix(10))
        return Card {
            SectionLabel(text: "Personal records")
            if records.isEmpty {
                Text("Your best lifts appear here.").font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            ForEach(records) { r in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.exercise).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text("\(r.sessions) session\(r.sessions == 1 ? "" : "s") · \(Int(r.totalVolume).formatted()) kg total")
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(r.bestWeight > 0 ? StrengthStats.weight(r.bestWeight) : "bodyweight")
                            .font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                        if r.bestOneRepMax > 0 {
                            Text("est. 1RM \(StrengthStats.weight(r.bestOneRepMax.rounded()))")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

struct StrengthSessionRow: View {
    var workout: StrengthWorkout

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(Theme.recoveryGreen)
                .frame(width: 40, height: 40)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text("\(workout.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(Format.duration(workout.duration)) · \(workout.sets.count) sets")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("\(Int(workout.volume).formatted()) kg")
                .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.textSecondary)
        }
    }
}

struct StrengthEditorView: View {
    @EnvironmentObject private var store: HealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var workout: StrengthWorkout
    @State private var exercise = StrengthStats.library[0]
    @State private var customExercise = ""
    @State private var reps = 8
    @State private var weight: Double = 40
    @State private var confirmDelete = false

    init(workout: StrengthWorkout) {
        _workout = State(initialValue: workout)
    }

    private var isExisting: Bool { store.strengthWorkouts.contains { $0.id == workout.id } }

    private var exerciseOptions: [String] {
        var options = StrengthStats.library
        for r in StrengthStats.records(store.strengthWorkouts) where !options.contains(r.exercise) {
            options.append(r.exercise)
        }
        return options
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Name", text: $workout.name)
                    DatePicker("Start", selection: $workout.start)
                    DatePicker("End", selection: $workout.end, in: workout.start...)
                    LabeledContent("Duration", value: Format.duration(workout.duration))
                }
                .listRowBackground(Theme.card)

                Section("Add a set") {
                    Picker("Exercise", selection: $exercise) {
                        ForEach(exerciseOptions, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("…or type another exercise", text: $customExercise)
                    Stepper("Reps  \(reps)", value: $reps, in: 1...100)
                    Stepper("Weight  \(StrengthStats.weight(weight))", value: $weight, in: 0...500, step: 2.5)
                    Button("Add set") { addSet() }
                        .font(.body.weight(.semibold))
                }
                .listRowBackground(Theme.card)

                Section {
                    if workout.sets.isEmpty {
                        Text("No sets yet").foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(workout.sets) { s in
                        HStack {
                            Text(s.exercise)
                            Spacer()
                            Text("\(s.reps) × \(StrengthStats.weight(s.weightKg))")
                                .monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .onDelete { offsets in workout.sets.remove(atOffsets: offsets) }
                } header: {
                    Text("Sets (\(workout.sets.count)) · \(Int(workout.volume).formatted()) kg volume")
                }
                .listRowBackground(Theme.card)

                if isExisting {
                    Section {
                        Button("Delete session", role: .destructive) { confirmDelete = true }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isExisting ? "Edit session" : "New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.saveStrength(workout)
                        dismiss()
                    }
                    .disabled(workout.end <= workout.start)
                }
            }
            .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteStrength(workout)
                    dismiss()
                }
            }
        }
    }

    private func addSet() {
        let custom = customExercise.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = custom.isEmpty ? exercise : custom
        workout.sets.append(StrengthSet(exercise: name, reps: reps, weightKg: weight))
    }
}
