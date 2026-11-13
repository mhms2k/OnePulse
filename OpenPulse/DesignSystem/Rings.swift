import SwiftUI

/// Animated circular gauge used for Recovery, Strain and Sleep.
struct ScoreRing: View {
    var progress: Double          // 0...1
    var color: Color
    var lineWidth: CGFloat = 10
    var gradient: Bool = true

    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(
                    gradient
                        ? AnyShapeStyle(AngularGradient(colors: [color.opacity(0.55), color], center: .center,
                                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(animated, 0.01))))
                        : AnyShapeStyle(color),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: lineWidth * 0.6)
        }
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.85)) { animated = clamped } }
        .onChange(of: progress) { _, _ in withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) { animated = clamped } }
    }

    private var clamped: Double { min(max(progress, 0), 1) }
}

/// A ring with a value and caption in the middle, used in the Today hero.
struct MetricRing: View {
    var title: String
    var value: String
    var unit: String?
    var progress: Double
    var color: Color
    var size: CGFloat = 104
    var caption: String?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ScoreRing(progress: progress, color: color, lineWidth: size * 0.085)
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(value).font(.score(size * 0.27))
                        if let unit { Text(unit).font(.score(size * 0.13, weight: .semibold)).foregroundStyle(Theme.textSecondary) }
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    if let caption {
                        Text(caption).font(.system(size: size * 0.095, weight: .medium)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(size * 0.14)
            }
            .frame(width: size, height: size)
            Text(title.uppercased()).font(.label).tracking(1.1).foregroundStyle(color)
        }
    }
}

/// Horizontal progress bar with an optional highlighted target band.
struct RangeBar: View {
    var value: Double
    var maxValue: Double
    var color: Color
    var target: ClosedRange<Double>? = nil
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                if let target {
                    Capsule()
                        .fill(color.opacity(0.22))
                        .frame(width: w * CGFloat((target.upperBound - target.lowerBound) / maxValue))
                        .offset(x: w * CGFloat(target.lowerBound / maxValue))
                }
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, w * CGFloat(min(value, maxValue) / maxValue)))
            }
        }
        .frame(height: height)
    }
}
