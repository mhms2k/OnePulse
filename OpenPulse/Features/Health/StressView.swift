import SwiftUI
import Charts

struct StressView: View {
    let day: Date
    @EnvironmentObject private var store: HealthStore
    @State private var samples: [StressSample] = []

    var body: some View {
        DetailScaffold(title: "Stress") {
            if let s = StressMonitor.summary(samples) {
                Card {
                    SectionLabel(text: "Stress monitor", trailing: day.formatted(.dateTime.weekday(.wide).month().day()))
                    StressSummaryRow(summary: s)
                }
                chartCard
                breakdownCard(s)
            } else {
                Card {
                    Text("No stress data for this day yet. Stress is calculated from your watch's stress readings, or from your heart rate compared with your resting heart rate.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
            NavigationLink {
                BreathworkView()
            } label: {
                Label("Calm down with a breathing session", systemImage: "wind")
                    .font(.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(Theme.textPrimary)
            }
            explainer
        }
        .task(id: day) { samples = store.stressTimeline(for: day) }
    }

    private var chartCard: some View {
        Card {
            SectionLabel(text: "Through the day", trailing: "0 – 3")
            Chart(samples) { s in
                AreaMark(x: .value("Time", s.date), y: .value("Stress", s.level))
                    .foregroundStyle(LinearGradient(colors: [Theme.recoveryYellow.opacity(0.35), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", s.date), y: .value("Stress", s.level))
                    .foregroundStyle(Theme.recoveryYellow)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...3)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel(format: .dateTime.hour()).foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0.0, 1.0, 2.0, 3.0]) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 170)
        }
    }

    private func breakdownCard(_ s: StressSummary) -> some View {
        Card {
            SectionLabel(text: "Time in each level")
            levelRow("Low (0–1)", s.low, Theme.recoveryGreen)
            levelRow("Medium (1–2)", s.medium, Theme.recoveryYellow)
            levelRow("High (2–3)", s.high, Theme.recoveryRed)
        }
    }

    private func levelRow(_ label: String, _ share: Double, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary).frame(width: 96, alignment: .leading)
            RangeBar(value: share, maxValue: 1, color: color, height: 8)
            Text("\(Int((share * 100).rounded()))%").font(.caption.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Theme.textPrimary).frame(width: 40, alignment: .trailing)
        }
    }

    private var explainer: some View {
        Card {
            SectionLabel(text: "How stress works")
            Text("Stress runs from 0 to 3. When your watch records its own stress readings they are used directly; otherwise OpenPulse compares your heart rate in 15-minute blocks with your resting heart rate. Workouts and the 15 minutes after them are left out, so training doesn't count as stress. A walk or climbing stairs can still raise it — check what you were doing before worrying.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct StressSummaryRow: View {
    var summary: StressSummary

    var body: some View {
        let current = summary.latest?.level ?? summary.average
        HStack(spacing: 16) {
            ZStack {
                ScoreRing(progress: current / 3, color: Theme.stress(current), lineWidth: 8)
                Text(String(format: "%.1f", current)).font(.score(20))
            }
            .frame(width: 66, height: 66)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(StressMonitor.label(current)) stress").font(.headline).foregroundStyle(Theme.textPrimary)
                if let latest = summary.latest {
                    Text("Latest at \(Format.clock(latest.date))").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Text(String(format: "Day average %.1f · high %d%% of the time", summary.average, Int((summary.high * 100).rounded())))
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }
}
