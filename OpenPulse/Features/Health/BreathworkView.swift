import SwiftUI
import Combine

struct BreathPattern: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var purpose: String
    var inhale: Double
    var holdIn: Double
    var exhale: Double
    var holdOut: Double

    var cycle: Double { inhale + holdIn + exhale + holdOut }

    static let all: [BreathPattern] = [
        BreathPattern(name: "Relax", purpose: "Long, slow exhales calm your nervous system and lower your heart rate. Good before bed or after a stressful moment.",
                      inhale: 4, holdIn: 0, exhale: 6, holdOut: 0),
        BreathPattern(name: "Focus", purpose: "Box breathing — even counts in, hold, out, hold — to steady yourself before something important.",
                      inhale: 4, holdIn: 4, exhale: 4, holdOut: 4),
        BreathPattern(name: "Alert", purpose: "Quicker, energising breaths to wake up before training or when you feel sluggish.",
                      inhale: 2, holdIn: 0, exhale: 2, holdOut: 0),
    ]

    /// Phase name, circle scale (0.5...1) and phase index at `t` seconds into the session.
    func phase(at t: Double) -> (name: String, scale: Double, index: Int) {
        var x = t.truncatingRemainder(dividingBy: cycle)
        if x < inhale { return ("Breathe in", 0.5 + 0.5 * x / inhale, 0) }
        x -= inhale
        if x < holdIn { return ("Hold", 1, 1) }
        x -= holdIn
        if x < exhale { return ("Breathe out", 1 - 0.5 * x / exhale, 2) }
        return ("Hold", 0.5, 3)
    }
}

struct BreathworkView: View {
    @State private var pattern = BreathPattern.all[0]
    @State private var minutes = 3
    @State private var startedAt: Date?
    @State private var elapsed: Double = 0
    @State private var phaseIndex = 0
    @State private var finished = false

    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var isRunning: Bool { startedAt != nil }

    var body: some View {
        DetailScaffold(title: "Breathwork") {
            Card {
                Picker("Pattern", selection: $pattern) {
                    ForEach(BreathPattern.all) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(isRunning)
                Text(pattern.purpose).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Length", selection: $minutes) {
                    Text("1 min").tag(1)
                    Text("3 min").tag(3)
                    Text("5 min").tag(5)
                }
                .pickerStyle(.segmented)
                .disabled(isRunning)
            }
            Card {
                let p = pattern.phase(at: elapsed)
                ZStack {
                    Circle().fill(Theme.stageREM.opacity(0.12))
                    Circle()
                        .fill(RadialGradient(colors: [Theme.stageREM.opacity(0.85), Theme.strain.opacity(0.5)],
                                             center: .center, startRadius: 10, endRadius: 140))
                        .scaleEffect(isRunning ? p.scale : 0.5)
                    VStack(spacing: 4) {
                        Text(isRunning ? p.name : (finished ? "Nicely done" : "Ready"))
                            .font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                        if isRunning {
                            Text(remainingText).font(.caption.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .frame(height: 260)
                .frame(maxWidth: .infinity)

                Button {
                    toggle()
                } label: {
                    Text(isRunning ? "Stop" : "Start")
                        .font(.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(isRunning ? Theme.cardRaised : Theme.stageREM,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(isRunning ? Theme.textPrimary : Color.black)
                }
            }
        }
        .onReceive(tick) { _ in
            guard let s = startedAt else { return }
            elapsed = Date().timeIntervalSince(s)
            let idx = pattern.phase(at: elapsed).index
            if idx != phaseIndex { phaseIndex = idx }
            if elapsed >= Double(minutes * 60) {
                startedAt = nil
                elapsed = 0
                finished = true
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: phaseIndex)
        .onDisappear { startedAt = nil }
    }

    private var remainingText: String {
        let left = max(0, Int(Double(minutes * 60) - elapsed))
        return String(format: "%d:%02d left", left / 60, left % 60)
    }

    private func toggle() {
        if isRunning {
            startedAt = nil
            elapsed = 0
        } else {
            finished = false
            elapsed = 0
            phaseIndex = 0
            startedAt = Date()
        }
    }
}
