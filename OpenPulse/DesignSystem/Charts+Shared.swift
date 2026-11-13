import SwiftUI
import Charts

struct DatedValue: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var value: Double
}

/// Daily bar chart used across detail and trend screens.
struct DailyBarChart: View {
    var values: [DatedValue]
    var yDomain: ClosedRange<Double>
    var color: (Double) -> Color
    var valueLabel: (Double) -> String = { "\(Int($0.rounded()))" }
    var height: CGFloat = 150

    @State private var selected: Date?

    var body: some View {
        Chart(values) { v in
            BarMark(x: .value("Day", v.date, unit: .day), y: .value("Value", v.value), width: .ratio(0.62))
                .foregroundStyle(color(v.value).gradient)
                .cornerRadius(4)
                .opacity(selected == nil || Calendar.current.isDate(selected!, inSameDayAs: v.date) ? 1 : 0.35)
            if let selected, Calendar.current.isDate(selected, inSameDayAs: v.date) {
                RuleMark(x: .value("Day", v.date, unit: .day))
                    .foregroundStyle(Theme.textTertiary)
                    .annotation(position: .top) {
                        VStack(spacing: 1) {
                            Text(valueLabel(v.value)).font(.caption.weight(.bold)).foregroundStyle(Theme.textPrimary)
                            Text(v.date.formatted(.dateTime.month(.abbreviated).day())).font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(6)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow).day(), centered: true)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel().foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(height: height)
    }
}

/// Simple line chart with a dotted personal baseline.
struct TrendLineChart: View {
    var values: [DatedValue]
    var color: Color
    var baseline: Double?
    var unit: String
    var height: CGFloat = 140

    var body: some View {
        let lo = (values.map(\.value).min() ?? 0)
        let hi = (values.map(\.value).max() ?? 1)
        let pad = max(2, (hi - lo) * 0.25)
        Chart {
            ForEach(values) { v in
                LineMark(x: .value("Day", v.date, unit: .day), y: .value(unit, v.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                PointMark(x: .value("Day", v.date, unit: .day), y: .value(unit, v.value))
                    .foregroundStyle(color)
                    .symbolSize(18)
            }
            if let baseline {
                RuleMark(y: .value("Baseline", baseline))
                    .foregroundStyle(Theme.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("your normal").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.month(.narrow).day()).foregroundStyle(Theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel().foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(height: height)
    }
}

/// Container for detail screens.
struct DetailScaffold<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 16) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
    }
}

struct StatCell: View {
    var label: String
    var value: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            Text(value).font(.score(20, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            if let sub { Text(sub).font(.caption2).foregroundStyle(Theme.textTertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
