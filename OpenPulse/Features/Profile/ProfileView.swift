import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: HealthStore
    @State private var confirmErase = false

    private var wakeBinding: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: store.profile.wakeMinutes / 60, minute: store.profile.wakeMinutes % 60,
                                  second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            store.profile.wakeMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 0)
        })
    }

    private var maxHRBinding: Binding<Double> {
        Binding(get: { Double(store.profile.maxHeartRate) },
                set: { store.profile.maxHeartRateOverride = Int($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Name", text: $store.profile.name)
                    Stepper("Age  \(store.profile.age)", value: $store.profile.age, in: 13...95)
                    Picker("Sex", selection: $store.profile.sex) {
                        ForEach(UserProfile.Sex.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Weight  \(Int(store.profile.weightKg)) kg", value: $store.profile.weightKg, in: 35...200, step: 1)
                }
                .listRowBackground(Theme.card)

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Max heart rate")
                            Spacer()
                            Text("\(store.profile.maxHeartRate) bpm").monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                        Slider(value: maxHRBinding, in: 150...215, step: 1).tint(Theme.strain)
                    }
                    if store.profile.maxHeartRateOverride != nil {
                        Button("Use age estimate (\(store.profile.estimatedMaxHeartRate) bpm)") {
                            store.profile.maxHeartRateOverride = nil
                        }
                    }
                } header: {
                    Text("Heart rate zones")
                } footer: {
                    Text("Strain zones are based on your max heart rate. If you've seen a higher value in a hard effort, set it here.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Stepper("Baseline need  \(Format.duration(store.profile.baselineSleepHours * 3600))",
                            value: $store.profile.baselineSleepHours, in: 6...10, step: 0.25)
                    DatePicker("Usual wake time", selection: wakeBinding, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Sleep")
                } footer: {
                    Text("Your nightly need starts from this baseline and adds time for strain and sleep debt, minus naps. Once a week of nights is recorded, bedtime advice uses your real wake times.")
                }
                .listRowBackground(Theme.card)

                Section("Data") {
                    if store.hasDemoData {
                        Button("Remove demo data") { store.deleteAll(source: DemoData.source) }
                    } else {
                        Button("Load demo data") { store.loadDemoData() }
                    }
                    Button("Recalculate all scores") { store.recomputeAll() }
                    Button("Erase all health data", role: .destructive) { confirmErase = true }
                }
                .listRowBackground(Theme.card)

                Section("About") {
                    NavigationLink("How the scores work") { MethodologyView() }
                    LabeledContent("Storage", value: "On this iPhone only")
                    LabeledContent("Days scored", value: "\(store.scores.count)")
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .confirmationDialog("Erase all health data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { store.deleteAll() }
            } message: {
                Text("This deletes every sample and score stored on this iPhone. Paired devices stay paired.")
            }
        }
    }
}

struct MethodologyView: View {
    var body: some View {
        DetailScaffold(title: "How the scores work") {
            section("Recovery · 0–100%", color: Theme.recoveryGreen,
                    "Measured every morning from the night just finished and compared with your own 30-day normal (the first 4 nights calibrate it).\n\n• Autonomic signal (50%): heart rate variability (RMSSD) when your device provides beat-to-beat data; otherwise the watch's overnight stress index, inverted.\n• Resting heart rate (30%): the lowest quarter of your sleeping heart rate.\n• Sleep performance (20%): hours slept vs hours needed.\n• Blood oxygen (10%): only counts when it's lower than normal.\n\nEach input becomes a z-score against your baseline, they are weighted, and a logistic curve maps the result to 1–99%. Green ≥ 67, yellow 34–66, red ≤ 33.")
            section("Strain · 0–21", color: Theme.strain,
                    "Cardiovascular load from Banister's TRIMP: every minute above 25% of your heart-rate reserve adds load that grows exponentially with intensity. The total is mapped onto a logarithmic 0–21 scale, so the top of the scale takes disproportionately more effort. Recovery sets today's target: green 14–18, yellow 10–14, red under 10.")
            section("Sleep · performance %", color: Theme.sleep,
                    "Sleep need = your baseline + up to 50 min after a high-strain day + a share of the last three nights' shortfall vs. baseline (debt) − naps. Performance is hours asleep divided by that need. Efficiency is time asleep vs time in bed; consistency compares your last four bed and wake times.")
            section("Healthspan · body age", color: Theme.recoveryGreen,
                    "Starts from your calendar age and adds or removes years for eight markers over the last 30 days (at least 14 days of data): estimated VO₂ max (15.3 × max HR ÷ resting HR), resting heart rate, hours of sleep, sleep consistency, minutes in zones 1–3 and 4–5, strength training time and daily steps. Pace of aging = 1 + (total years ÷ 6), shown from −1× to 3×. A motivational estimate, not a medical test.")
            section("Stress · 0–3", color: Theme.recoveryYellow,
                    "Uses your watch's own stress readings when available; otherwise your heart rate in 15-minute blocks compared with your resting heart rate (beyond the ~15% rise that is normal when awake). Workouts and the 15 minutes after them are excluded.")
            section("Journal · behavior insights", color: Theme.strain,
                    "Each morning, answer yes/no about the day before. Once a habit has at least 5 yes and 5 no answers on days with a Recovery score in the last 90 days, OpenPulse shows the average Recovery after each. These are associations, not proof of cause.")
            section("Your data", color: Theme.neutral,
                    "OpenPulse connects to devices directly over Bluetooth and stores everything on this iPhone. Nothing is uploaded. Scores are wellness estimates, not medical advice.\n\nCMF watch protocol knowledge comes from the open-source Gadgetbridge community's reverse-engineering work.")
        }
    }

    private func section(_ title: String, color: Color, _ body: String) -> some View {
        Card {
            Text(title).font(.headline).foregroundStyle(color)
            Text(body).font(.subheadline).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
