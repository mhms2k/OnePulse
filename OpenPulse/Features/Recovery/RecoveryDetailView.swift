import SwiftUI
import Charts

struct RecoveryDetailView: View {
    let day: Date
    @EnvironmentObject private var store: HealthStore

    var body: some View {
        DetailScaffold(title: "Recovery") {
            if let s = store.score(for: day) {
                summary(s)
                if s.recovery != nil { contributorsCard(s) }
                historyCard
                vitalsTrends
                explainer
            }
        }
    }

    private func summary(_ s: DayScore) -> some View {
        let color = Theme.recovery(s.recovery)
        return Card {
            VStack(spacing: 14) {
                ZStack {
                    ScoreRing(progress: (s.recovery ?? 0) / 100, color: color, lineWidth: 16)
                    VStack(spacing: 2) {
                        Text(s.recovery.map { "\(Int($0))%" } ?? "—").font(.score(48))
                        Text(s.recovery.map { RecoveryZone($0).title } ?? "Calibrating")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(color)
                    }
                }
                .frame(width: 190, height: 190)
                .frame(maxWidth: .infinity)

                if s.recovery == nil {
                    Text("Recovery compares each night to your own baseline. Sleep with your watch on for \(max(1, s.nightsUntilCalibrated)) more night(s) and it switches on.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                } else if let rec = s.recovery {
                    let t = RecoveryZone(rec).strainTarget
                    Pill(text: "Optimal strain today \(Int(t.lowerBound))–\(Int(t.upperBound))", color: Theme.strain, symbol: "target")
                }
            }
        }
    }

    private func contributorsCard(_ s: DayScore) -> some View {
        let items = store.engine.contributors(for: s)
        return Card {
            SectionLabel(text: "What drove your score")
            ForEach(items) { c in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(c.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(c.value).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                    }
                    ImpactBar(z: c.z)
                    HStack {
                        Text(c.detail).font(.caption).foregroundStyle(Theme.textTertiary)
                        Spacer()
                        Text("weight \(Int(c.weight * 100))%").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
                if c.id != items.last?.id { Divider().overlay(Theme.stroke) }
            }
        }
    }

    private var historyCard: some View {
        let recent = store.scores.filter { $0.day <= day && $0.recovery != nil }.suffix(30)
        return Card {
            SectionLabel(text: "Last 30 days", trailing: Stats.mean(recent.compactMap(\.recovery)).map { "avg \(Int($0))%" })
            if recent.isEmpty {
                Text("Your first Recovery score appears after the calibration nights.").font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                DailyBarChart(values: recent.map { DatedValue(date: $0.day, value: $0.recovery ?? 0) },
                              yDomain: 0...100, color: { Theme.recovery($0) }, valueLabel: { "\(Int($0))%" })
            }
        }
    }

    @ViewBuilder private var vitalsTrends: some View {
        let recent = Array(store.scores.filter { $0.day <= day }.suffix(30))
        let rhr = recent.compactMap { s in s.restingHR.map { DatedValue(date: s.day, value: $0) } }
        if rhr.count >= 2 {
            Card {
                SectionLabel(text: "Resting heart rate", trailing: "bpm")
                TrendLineChart(values: rhr, color: Theme.recoveryRed, baseline: store.score(for: day)?.rhrBaseline?.mean, unit: "bpm")
            }
        }
        let hrv = recent.compactMap { s in s.hrv.map { DatedValue(date: s.day, value: $0) } }
        let stress = recent.compactMap { s in s.overnightStress.map { DatedValue(date: s.day, value: $0) } }
        if hrv.count >= 2 {
            Card {
                SectionLabel(text: "Heart rate variability", trailing: "ms")
                TrendLineChart(values: hrv, color: Theme.recoveryGreen,
                               baseline: store.score(for: day)?.hrvBaseline.map { exp($0.mean) }, unit: "ms")
            }
        } else if stress.count >= 2 {
            Card {
                SectionLabel(text: "Overnight stress", trailing: "lower is better")
                TrendLineChart(values: stress, color: Theme.recoveryYellow, baseline: store.score(for: day)?.stressBaseline?.mean, unit: "")
            }
        }
    }

    private var explainer: some View {
        Card {
            SectionLabel(text: "How recovery works")
            Text("Each morning OpenPulse compares last night to your personal 30-day normal. Your autonomic signal carries the most weight — true HRV when your device records beat-to-beat data, otherwise your watch's overnight stress index. Resting heart rate, sleep performance and blood oxygen add context. Green (67–99%) means you're ready for strain, yellow (34–66%) means maintain, red (1–33%) means recover.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Diverging bar: left = pulled score down, right = pushed it up.
struct ImpactBar: View {
    var z: Double

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let w = half * CGFloat(min(abs(z), 3) / 3)
            let color = z >= 0 ? Theme.recoveryGreen : Theme.recoveryRed
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Rectangle().fill(Theme.textTertiary).frame(width: 2).offset(x: half - 1)
                Capsule().fill(color)
                    .frame(width: max(4, w))
                    .offset(x: z >= 0 ? half : half - max(4, w))
            }
        }
        .frame(height: 6)
    }
}
