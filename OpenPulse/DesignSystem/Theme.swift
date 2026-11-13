import SwiftUI

enum Theme {
    // Surfaces
    static let background = Color(hex: 0x07090C)
    static let card = Color(hex: 0x12161C)
    static let cardRaised = Color(hex: 0x1A2028)
    static let stroke = Color.white.opacity(0.07)
    static let track = Color.white.opacity(0.08)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    // Metrics
    static let recoveryGreen = Color(hex: 0x2EE59D)
    static let recoveryYellow = Color(hex: 0xFFC94A)
    static let recoveryRed = Color(hex: 0xFF5C6C)
    static let strain = Color(hex: 0x3EA8FF)
    static let sleep = Color(hex: 0x9C8CFF)
    static let neutral = Color(hex: 0x8A96A8)

    // Sleep stages
    static let stageAwake = Color(hex: 0xF4F1E8)
    static let stageLight = Color(hex: 0x7FA7FF)
    static let stageDeep = Color(hex: 0x6B4CFF)
    static let stageREM = Color(hex: 0x37D5E6)

    // Heart-rate zones 1–5
    static let zones: [Color] = [Color(hex: 0x5E7A99), Color(hex: 0x3EA8FF), Color(hex: 0x2EE59D),
                                 Color(hex: 0xFFC94A), Color(hex: 0xFF5C6C)]

    static func recovery(_ score: Double?) -> Color {
        guard let score else { return neutral }
        switch RecoveryZone(score) {
        case .green: return recoveryGreen
        case .yellow: return recoveryYellow
        case .red: return recoveryRed
        }
    }

    static func stage(_ s: SleepStage) -> Color {
        switch s {
        case .awake: return stageAwake
        case .light: return stageLight
        case .deep: return stageDeep
        case .rem: return stageREM
        }
    }

    static func tone(_ t: Insight.Tone) -> Color {
        switch t {
        case .positive: return recoveryGreen
        case .neutral: return strain
        case .caution: return recoveryYellow
        }
    }

    /// Stress monitor colours: 0–1 low, 1–2 medium, 2–3 high.
    static func stress(_ level: Double) -> Color {
        level < 1 ? recoveryGreen : (level < 2 ? recoveryYellow : recoveryRed)
    }

    /// Pace of aging: below 1 is slower than average.
    static func pace(_ value: Double) -> Color {
        value < 1 ? recoveryGreen : (value < 1.5 ? recoveryYellow : recoveryRed)
    }

    static let radius: CGFloat = 22
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }
}

extension Font {
    /// Rounded numerals for scores, à la sports instruments.
    static func score(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static let label = Font.system(size: 11, weight: .semibold).width(.expanded)
}

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

struct SectionLabel: View {
    var text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text.uppercased()).font(.label).tracking(1.2).foregroundStyle(Theme.textTertiary)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// "+4 bpm vs normal" style badge. `goodWhenUp` controls the color logic.
struct DeltaBadge: View {
    var delta: Double
    var unit: String
    var goodWhenUp: Bool
    var decimals: Int = 0

    var body: some View {
        let good = goodWhenUp ? delta >= 0 : delta <= 0
        let small = abs(delta) < (decimals == 0 ? 1 : 0.2)
        let color = small ? Theme.textSecondary : (good ? Theme.recoveryGreen : Theme.recoveryYellow)
        HStack(spacing: 2) {
            Image(systemName: small ? "equal" : (delta > 0 ? "arrow.up" : "arrow.down"))
                .font(.system(size: 9, weight: .heavy))
            Text(small ? "normal" : "\(String(format: "%.\(decimals)f", abs(delta)))\(unit)")
                .font(.caption2.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct Pill: View {
    var text: String
    var color: Color
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.14), in: Capsule())
    }
}
