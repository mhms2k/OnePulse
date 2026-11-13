import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var store: HealthStore
    @State private var range = 30

    private var window: [DayScore] { Array(store.scores.suffix(range)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Range", selection: $range) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                    .pickerStyle(.segmented)

                    if window.isEmpty {
                        Card { Text("Trends appear once you have a few days of data.").foregroundStyle(Theme.textSecondary) }
                    } else {
                        averagesCard
                        chartCard("Recovery", unit: "%", values: window.compactMap { s in s.recovery.map { DatedValue(date: s.day, value: $0) } },
                                  domain: 0...100, color: { Theme.recovery($0) }, label: { "\(Int($0))%" })
                        chartCard("Day strain", unit: "", values: window.map { DatedValue(date: $0.day, value: $0.strain) },
                                  domain: 0...21, color: { _ in Theme.strain }, label: { String(format: "%.1f", $0) })
                        chartCard("Sleep performance", unit: "%", values: window.compactMap { s in s.sleepPerformance.map { DatedValue(date: s.day, value: $0) } },
                                  domain: 0...100, color: { _ in Theme.sleep }, label: { "\(Int($0))%" })
                        hoursCard
                        lineCard("Resting heart rate", "bpm", Theme.recoveryRed,
                                 window.compactMap { s in s.restingHR.map { DatedValue(date: s.day, value: $0) } })
                        let hrv = window.compactMap { s in s.hrv.map { DatedValue(date: s.day, value: $0) } }
                        if hrv.count >= 2 {
                            lineCard("HRV (RMSSD)", "ms", Theme.recoveryGreen, hrv)
                        } else {
                            lineCard("Overnight stress", "", Theme.recoveryYellow,
                                     window.compactMap { s in s.overnightStress.map { DatedValue(date: s.day, value: $0) } })
                        }
                        correlationCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Trends")
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
    }

    private var averagesCard: some View {
        Card {
            SectionLabel(text: "\(range)-day averages")
            Grid(horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    StatCell(label: "Recovery", value: avg(window.compactMap(\.recovery)).map { "\(Int($0))%" } ?? "—")
                    StatCell(label: "Strain", value: avg(window.map(\.strain)).map { String(format: "%.1f", $0) } ?? "—")
                    StatCell(label: "Sleep", value: avg(window.filter(\.hasSleep).map(\.asleep)).map { Format.duration($0) } ?? "—")
                }
                GridRow {
                    StatCell(label: "Resting HR", value: avg(window.compactMap(\.restingHR)).map { "\(Int($0))" } ?? "—")
                    StatCell(label: "Green days", value: "\(window.compactMap(\.recovery).filter { $0 >= 67 }.count)")
                    StatCell(label: "Steps / day", value: avg(window.map { Double($0.steps) }.filter { $0 > 0 }).map { Int($0).formatted() } ?? "—")
                }
            }
        }
    }

    private func avg(_ xs: [Double]) -> Double? { Stats.mean(xs) }

    private func chartCard(_ title: String, unit: String, values: [DatedValue], domain: ClosedRange<Double>,
                           color: @escaping (Double) -> Color, label: @escaping (Double) -> String) -> some View {
        Card {
            SectionLabel(text: title, trailing: avg(values.map(\.value)).map { "avg " + label($0) })
            if values.isEmpty {
                Text("Not enough data yet").font(.footnote).foregroundStyle(Theme.textTertiary)
            } else {
                DailyBarChart(values: values, yDomain: domain, color: color, valueLabel: label)
            }
        }
    }

    private func lineCard(_ title: String, _ unit: String, _ color: Color, _ values: [DatedValue]) -> some View {
        Card {
            SectionLabel(text: title, trailing: avg(values.map(\.value)).map { "avg \(Int($0)) \(unit)" })
            if values.count < 2 {
                Text("Not enough data yet").font(.footnote).foregroundStyle(Theme.textTertiary)
            } else {
                TrendLineChart(values: values, color: color, baseline: avg(values.map(\.value)), unit: unit)
            }
        }
    }

    /// Hours slept vs hours needed, side by side.
    private var hoursCard: some View {
        let nights = window.filter(\.hasSleep)
        return Card {
            SectionLabel(text: "Hours vs need", trailing: "debt builds when purple falls short")
            Chart {
                ForEach(nights) { s in
                    BarMark(x: .value("Day", s.day, unit: .day), y: .value("Hours", s.asleep / 3600), width: .ratio(0.6))
                        .foregroundStyle(Theme.sleep.gradient)
                        .cornerRadius(3)
                    LineMark(x: .value("Day", s.day, unit: .day), y: .value("Need", s.sleepNeed / 3600))
                        .foregroundStyle(Theme.textSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .interpolationMethod(.stepCenter)
                }
            }
            .chartYScale(domain: 0...11)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow).day()).foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0.0, 4.0, 8.0]) { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 150)
        }
    }

    /// Simple data-driven observation: how sleep length relates to next-day recovery.
    private var correlationCard: some View {
        let pairs = window.compactMap { s -> (Double, Double)? in
            guard let r = s.recovery, s.hasSleep else { return nil }
            return (s.asleep / 3600, r)
        }
        let long = pairs.filter { $0.0 >= 7.5 }.map { $0.1 }
        let short = pairs.filter { $0.0 < 6.5 }.map { $0.1 }
        return Group {
            if let a = avg(long), let b = avg(short), long.count >= 3, short.count >= 3 {
                Card {
                    SectionLabel(text: "Your pattern")
                    HStack(spacing: 14) {
                        Image(systemName: "lightbulb.max.fill").font(.title2).foregroundStyle(Theme.recoveryYellow)
                        Text("On nights with 7.5h+ of sleep your recovery averages **\(Int(a))%**, versus **\(Int(b))%** after nights under 6.5h.")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}
