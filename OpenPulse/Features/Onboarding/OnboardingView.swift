import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: HealthStore
    @State private var page = 0
    @State private var draft = UserProfile.load()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(colors: [Theme.strain.opacity(0.18), .clear], center: .top, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcome.tag(0)
                    profile.tag(1)
                    finish.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(i == page ? Theme.textPrimary : Theme.track)
                            .frame(width: i == page ? 22 : 7, height: 7)
                    }
                }
                .animation(.snappy, value: page)
                .padding(.bottom, 18)
            }
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                ScoreRing(progress: 0.82, color: Theme.recoveryGreen, lineWidth: 12).frame(width: 190, height: 190)
                ScoreRing(progress: 0.64, color: Theme.strain, lineWidth: 12).frame(width: 150, height: 150)
                ScoreRing(progress: 0.91, color: Theme.sleep, lineWidth: 12).frame(width: 110, height: 110)
            }
            VStack(spacing: 12) {
                Text("OpenPulse").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textPrimary)
                Text("Recovery, strain and sleep coaching for the wearable you already own. Direct Bluetooth, no subscriptions, your data stays on your phone.")
                    .font(.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }
            Spacer()
            primaryButton("Get started") { page = 1 }
        }
        .padding(.horizontal, 24)
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 30)
            Text("A few basics").font(.largeTitle.bold()).foregroundStyle(Theme.textPrimary)
            Text("Heart-rate zones and sleep need are personal. You can change these any time.")
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 0) {
                field("Age") {
                    Stepper("\(draft.age)", value: $draft.age, in: 13...95).fixedSize()
                }
                Divider().overlay(Theme.stroke)
                field("Sex") {
                    Picker("Sex", selection: $draft.sex) {
                        ForEach(UserProfile.Sex.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(width: 200)
                }
                Divider().overlay(Theme.stroke)
                field("Sleep need") {
                    Stepper(Format.duration(draft.baselineSleepHours * 3600), value: $draft.baselineSleepHours, in: 6...10, step: 0.25)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Estimated max heart rate: \(draft.estimatedMaxHeartRate) bpm")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
            Spacer()
            primaryButton("Continue") { page = 2 }
        }
        .padding(.horizontal, 24)
    }

    private var finish: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Theme.strain)
            Text("Connect your wearable").font(.title.bold()).foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 14) {
                bullet("applewatch.side.right", "CMF / Nothing watches", "Sleep stages, all-day heart rate, SpO₂, stress")
                bullet("heart.circle", "Any Bluetooth HR sensor", "Polar, Garmin, Wahoo, Coros… with real HRV")
            }
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer()
            primaryButton("Start using OpenPulse") { complete(demo: false) }
            Button("Try it with demo data first") { complete(demo: true) }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
    }

    // MARK: Helpers

    private func complete(demo: Bool) {
        draft.hasOnboarded = true
        store.profile = draft
        if demo { store.loadDemoData() }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textPrimary)
            Spacer()
            content()
        }
        .frame(minHeight: 54)
    }

    private func bullet(_ symbol: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.strain).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(sub).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(Color.black)
        }
        .padding(.bottom, 8)
    }
}
