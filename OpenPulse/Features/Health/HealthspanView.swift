import SwiftUI

struct HealthspanView: View {
    @EnvironmentObject private var store: HealthStore

    var body: some View {
        DetailScaffold(title: "Healthspan") {
            if let h = store.healthspan {
                summary(h)
                Card {
                    SectionLabel(text: "What moves your body age", trailing: "last \(h.daysUsed) days")
                    ForEach(h.metrics) { m in
                        MetricYearsRow(metric: m)
                        if m.id != h.metrics.last?.id { Divider().overlay(Theme.stroke) }
                    }
                }
            } else {
                Card {
                    Image(systemName: "hourglass").font(.title).foregroundStyle(Theme.strain)
                    Text("Your body age needs about two weeks of sleep and heart-rate data. Keep wearing your watch, day and night.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
            explainer
        }
    }

    static func differenceText(_ h: HealthspanResult) -> String {
        let d = h.difference
        if abs(d) < 0.25 { return "Right in line with your calendar age of \(h.chronologicalAge)." }
        let years = String(format: "%.1f", abs(d))
        return d < 0
            ? "\(years) years younger than your calendar age of \(h.chronologicalAge)."
            : "\(years) years older than your calendar age of \(h.chronologicalAge)."
    }

    private func summary(_ h: HealthspanResult) -> some View {
        Card {
            HStack(spacing: 20) {
                ZStack {
                    ScoreRing(progress: min(max(h.bodyAge / 100, 0), 1),
                              color: h.difference <= 0 ? Theme.recoveryGreen : Theme.recoveryYellow, lineWidth: 12)
                    VStack(spacing: 0) {
                        Text(String(format: "%.1f", h.bodyAge)).font(.score(32))
                        Text("body age").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(width: 124, height: 124)
                VStack(alignment: .leading, spacing: 10) {
                    Text(Self.differenceText(h)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pace of aging").font(.caption).foregroundStyle(Theme.textSecondary)
                        Text(String(format: "%.1f×", h.paceOfAging)).font(.score(24, weight: .semibold))
                            .foregroundStyle(Theme.pace(h.paceOfAging))
                        Text(paceText(h.paceOfAging)).font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    private func paceText(_ p: Double) -> String {
        if p < 0.9 { return "aging slower than average" }
        if p <= 1.1 { return "aging at an average pace" }
        return "aging faster than average"
    }

    private var explainer: some View {
        Card {
            SectionLabel(text: "How it works")
            Text("Body age starts from your calendar age and adds or removes years for eight habits and fitness markers from the last 30 days: estimated VO₂ max, resting heart rate, sleep hours, sleep consistency, easy and hard cardio time, strength training and daily steps. Pace of aging shows how fast you're aging per calendar year at your current habits — 1.0× is average. It's a motivational estimate, not a medical test.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct MetricYearsRow: View {
    var metric: HealthspanMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(metric.name, systemImage: metric.symbol)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(yearsText).font(.caption.weight(.bold)).monospacedDigit()
                    .foregroundStyle(metric.years <= 0 ? Theme.recoveryGreen : Theme.recoveryRed)
            }
            ImpactBar(z: -metric.years)
            HStack {
                Text(metric.value).font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("goal \(metric.target)").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var yearsText: String {
        let sign = metric.years > 0 ? "+" : (metric.years < 0 ? "−" : "")
        return "\(sign)\(String(format: "%.1f", abs(metric.years))) yrs"
    }
}
