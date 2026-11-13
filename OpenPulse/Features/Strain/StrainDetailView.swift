import SwiftUI
import Charts

struct StrainDetailView: View {
    let day: Date
    @EnvironmentObject private var store: HealthStore
    @State private var detail: DayDetail?

    private static let zoneLabels = ["Zone 1 · 50–60%", "Zone 2 · 60–70%", "Zone 3 · 70–80%", "Zone 4 · 80–90%", "Zone 5 · 90–100%"]

    var body: some View {
        DetailScaffold(title: "Strain") {
            if let s = store.score(for: day) {
                summary(s)
                if let hr = detail?.heartRate, hr.count > 2 {
                    HeartRateDayChart(samples: hr, workouts: s.workouts, maxHR: store.profile.maxHeartRate)
                }
                zonesCard(s)
                if !s.workouts.isEmpty { WorkoutsCard(workouts: s.workouts) }
                historyCard
                explainer
            }
        }
        .task(id: day) { detail = store.detail(for: day) }
    }

    private func summary(_ s: DayScore) -> some View {
        let target = s.recovery.map { RecoveryZone($0).strainTarget }
        return Card {
            HStack(spacing: 20) {
                ZStack {
                    ScoreRing(progress: s.strain / 21, color: Theme.strain, lineWidth: 12)
                    VStack(spacing: 0) {
                        Text(String(format: "%.1f", s.strain)).font(.score(32))
                        Text("day strain").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 10) {
                    Text(level(s.strain)).font(.headline).foregroundStyle(Theme.textPrimary)
                    if let target {
                        Text("Optimal today: \(Int(target.lowerBound))–\(Int(target.upperBound))")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    HStack(spacing: 16) {
                        StatCell(label: "Avg HR", value: s.avgHR.map { "\($0)" } ?? "—")
                        StatCell(label: "Max HR", value: s.maxHR.map { "\($0)" } ?? "—")
                    }
                }
            }
            RangeBar(value: s.strain, maxValue: 21, color: Theme.strain, target: target, height: 8)
            HStack {
                Label(s.steps.formatted(), systemImage: "figure.walk")
                Spacer()
                Label("\(s.activeCalories) kcal", systemImage: "flame.fill")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func level(_ strain: Double) -> String {
        switch strain {
        case ..<10: return "Light day"
        case ..<14: return "Moderate strain"
        case ..<18: return "High strain"
        default: return "All out"
        }
    }

    private func zonesCard(_ s: DayScore) -> some View {
        let total = max(1, s.zoneMinutes.reduce(0, +))
        return Card {
            SectionLabel(text: "Heart rate zones", trailing: "% of max HR \(store.profile.maxHeartRate)")
            ForEach(Array(s.zoneMinutes.enumerated().reversed()), id: \.offset) { i, minutes in
                HStack(spacing: 10) {
                    Text(Self.zoneLabels[i]).font(.caption).foregroundStyle(Theme.textSecondary).frame(width: 110, alignment: .leading)
                    RangeBar(value: minutes, maxValue: total, color: Theme.zones[i], height: 8)
                    Text(Format.duration(minutes * 60)).font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Theme.textPrimary).frame(width: 54, alignment: .trailing)
                }
            }
        }
    }

    private var historyCard: some View {
        let recent = store.scores.filter { $0.day <= day }.suffix(14)
        return Card {
            SectionLabel(text: "Last 14 days", trailing: Stats.mean(recent.map(\.strain)).map { String(format: "avg %.1f", $0) })
            DailyBarChart(values: recent.map { DatedValue(date: $0.day, value: $0.strain) },
                          yDomain: 0...21, color: { _ in Theme.strain }, valueLabel: { String(format: "%.1f", $0) })
        }
    }

    private var explainer: some View {
        Card {
            SectionLabel(text: "How strain works")
            Text("Strain measures cardiovascular load on a 0–21 scale. Every minute your heart spends above about a quarter of its reserve (roughly a brisk walk) adds load — more at higher intensities, so time in zones 4–5 counts far more than an easy walk. The scale is logarithmic: going from 18 to 19 takes much more work than 8 to 9. Your zones use your own resting and max heart rate.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct HeartRateDayChart: View {
    var samples: [HRPoint]
    var workouts: [WorkoutScore]
    var maxHR: Int

    var body: some View {
        let lo = Double(samples.map(\.bpm).min() ?? 40)
        let hi = Double(samples.map(\.bpm).max() ?? 180)
        Card {
            SectionLabel(text: "Heart rate", trailing: "\(Int(lo))–\(Int(hi)) bpm")
            Chart {
                ForEach(workouts) { w in
                    RectangleMark(xStart: .value("Start", w.start), xEnd: .value("End", w.end),
                                  yStart: .value("Low", lo - 5), yEnd: .value("High", hi + 5))
                        .foregroundStyle(Theme.strain.opacity(0.12))
                }
                ForEach(samples, id: \.date) { p in
                    AreaMark(x: .value("Time", p.date), yStart: .value("Base", lo - 5), yEnd: .value("BPM", Double(p.bpm)))
                        .foregroundStyle(LinearGradient(colors: [Theme.recoveryRed.opacity(0.25), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", p.date), y: .value("BPM", Double(p.bpm)))
                        .foregroundStyle(Theme.recoveryRed)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: (lo - 5)...(hi + 5))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel(format: .dateTime.hour()).foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 180)
        }
    }
}
