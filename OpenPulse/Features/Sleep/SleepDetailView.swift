import SwiftUI
import Charts

struct SleepDetailView: View {
    let day: Date
    @EnvironmentObject private var store: HealthStore
    @State private var detail: DayDetail?

    var body: some View {
        DetailScaffold(title: "Sleep") {
            if let s = store.score(for: day), s.hasSleep {
                summary(s)
                if let sleep = detail?.sleep, !sleep.segments.isEmpty { HypnogramCard(record: sleep) }
                StagesCard(score: s)
                statsCard(s)
                needCard(s)
                historyCard
            } else {
                Card {
                    Text("No sleep recorded for this night.").foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .task(id: day) { detail = store.detail(for: day) }
    }

    private func summary(_ s: DayScore) -> some View {
        Card {
            HStack(spacing: 20) {
                ZStack {
                    ScoreRing(progress: (s.sleepPerformance ?? 0) / 100, color: Theme.sleep, lineWidth: 12)
                    VStack(spacing: 0) {
                        Text("\(Int(s.sleepPerformance ?? 0))%").font(.score(30))
                        Text("performance").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 12) {
                    labeledBar("Hours of sleep", Format.duration(s.asleep), s.asleep, Theme.sleep, max: max(s.asleep, s.sleepNeed))
                    labeledBar("Sleep needed", Format.duration(s.sleepNeed), s.sleepNeed, Theme.textTertiary, max: max(s.asleep, s.sleepNeed))
                    Text("\(Format.clock(s.bedtime)) – \(Format.clock(s.wakeTime))")
                        .font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func labeledBar(_ label: String, _ value: String, _ t: TimeInterval, _ color: Color, max m: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(value).font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
            }
            RangeBar(value: t, maxValue: max(m, 1), color: color, height: 7)
        }
    }

    private func statsCard(_ s: DayScore) -> some View {
        Card {
            SectionLabel(text: "Sleep quality")
            Grid(horizontalSpacing: 12, verticalSpacing: 16) {
                GridRow {
                    StatCell(label: "Efficiency", value: s.efficiency.map { "\(Int($0))%" } ?? "—", sub: "asleep vs in bed")
                    StatCell(label: "Consistency", value: s.consistency.map { "\(Int($0))%" } ?? "—", sub: "last 4 nights")
                }
                GridRow {
                    StatCell(label: "Restorative", value: Format.duration(s.restorative),
                             sub: s.asleep > 0 ? "\(Int(s.restorative / s.asleep * 100))% deep + REM" : nil)
                    StatCell(label: "Time in bed", value: Format.duration(s.timeInBed), sub: "\(Format.duration(s.awake)) awake")
                }
                GridRow {
                    StatCell(label: "Sleeping HR", value: s.restingHR.map { "\(Int($0)) bpm" } ?? "—", sub: "lowest quartile")
                    StatCell(label: "Blood oxygen", value: s.spo2.map { String(format: "%.1f%%", $0) } ?? "—", sub: "overnight avg")
                }
            }
        }
    }

    private func needCard(_ s: DayScore) -> some View {
        Card {
            SectionLabel(text: "Why you needed \(Format.duration(s.sleepNeed))")
            needRow("Baseline need", s.sleepNeedBaseline, "+")
            needRow("Strain from the day before", s.sleepNeedFromStrain, "+")
            needRow("Recent sleep debt", s.sleepNeedFromDebt, "+")
            needRow("Naps", s.sleepNeedFromNaps, "−")
        }
    }

    private func needRow(_ label: String, _ t: TimeInterval, _ sign: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(t < 60 ? "—" : "\(sign == "−" ? "−" : (label == "Baseline need" ? "" : "+"))\(Format.duration(t))")
                .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
        }
    }

    private var historyCard: some View {
        let recent = store.scores.filter { $0.day <= day && $0.sleepPerformance != nil }.suffix(14)
        return Card {
            SectionLabel(text: "Last 14 nights", trailing: avgText(recent.compactMap(\.sleepPerformance)))
            DailyBarChart(values: recent.map { DatedValue(date: $0.day, value: $0.sleepPerformance ?? 0) },
                          yDomain: 0...100, color: { _ in Theme.sleep }, valueLabel: { "\(Int($0))%" })
        }
    }

    private func avgText(_ xs: [Double]) -> String {
        guard let m = Stats.mean(xs) else { return "" }
        return "avg \(Int(m))%"
    }
}

// MARK: - Hypnogram

struct HypnogramCard: View {
    var record: SleepRecord

    /// Segments with gaps filled in as awake so the chart is continuous.
    private var segments: [SleepSegment] {
        var out: [SleepSegment] = []
        var cursor = record.start
        for seg in record.segments.sorted(by: { $0.start < $1.start }) {
            if seg.start.timeIntervalSince(cursor) > 60 {
                out.append(SleepSegment(start: cursor, duration: seg.start.timeIntervalSince(cursor), stage: .awake))
            }
            out.append(seg)
            cursor = max(cursor, seg.end)
        }
        if record.end.timeIntervalSince(cursor) > 60 {
            out.append(SleepSegment(start: cursor, duration: record.end.timeIntervalSince(cursor), stage: .awake))
        }
        return out
    }

    var body: some View {
        Card {
            SectionLabel(text: "Sleep stages", trailing: "\(Format.clock(record.start)) – \(Format.clock(record.end))")
            Chart(segments, id: \.start) { seg in
                let y = Double(3 - seg.stage.depth)
                RectangleMark(xStart: .value("Start", seg.start), xEnd: .value("End", seg.end),
                              yStart: .value("Stage", y - 0.42), yEnd: .value("Stage", y + 0.42))
                    .foregroundStyle(Theme.stage(seg.stage).gradient)
                    .cornerRadius(3)
            }
            .chartYScale(domain: -0.6...3.6)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.0, 1.0, 2.0, 3.0]) { v in
                    AxisValueLabel {
                        Text(label(v.as(Double.self) ?? 0)).font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel(format: .dateTime.hour()).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 170)
        }
    }

    private func label(_ y: Double) -> String {
        switch Int(y.rounded()) {
        case 3: return "Awake"
        case 2: return "REM"
        case 1: return "Light"
        default: return "Deep"
        }
    }
}

struct StagesCard: View {
    var score: DayScore

    var body: some View {
        Card {
            SectionLabel(text: "Stage breakdown")
            row(.awake, score.awake)
            row(.light, score.light)
            row(.deep, score.deep)
            row(.rem, score.rem)
        }
    }

    private func row(_ stage: SleepStage, _ t: TimeInterval) -> some View {
        let pct = score.timeInBed > 0 ? t / score.timeInBed : 0
        return HStack(spacing: 12) {
            Circle().fill(Theme.stage(stage)).frame(width: 9, height: 9)
            Text(stage.title).font(.subheadline).foregroundStyle(Theme.textPrimary).frame(width: 92, alignment: .leading)
            RangeBar(value: pct, maxValue: 1, color: Theme.stage(stage), height: 7)
            Text(Format.duration(t)).font(.caption.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Theme.textPrimary).frame(width: 56, alignment: .trailing)
            Text("\(Int((pct * 100).rounded()))%").font(.caption).monospacedDigit()
                .foregroundStyle(Theme.textTertiary).frame(width: 34, alignment: .trailing)
        }
    }
}
