import Foundation

struct CycleStatus: Hashable {
    enum Phase: String { case menstrual = "Menstrual", follicular = "Follicular", ovulatory = "Ovulatory", luteal = "Luteal" }
    var day: Int
    var length: Int
    var phase: Phase
    var nextPeriod: Date

    var guidance: String {
        switch phase {
        case .menstrual:
            return "Energy can be lower and resting heart rate often drops back to baseline. Gentle training and extra sleep are well tolerated."
        case .follicular:
            return "Rising estrogen usually brings better recovery and higher HRV. A good window for hard sessions and strength progress."
        case .ovulatory:
            return "Strength and power often peak around ovulation. Warm up well; ligaments can be a little looser."
        case .luteal:
            return "Progesterone raises resting heart rate and body temperature, and HRV tends to dip. Lower recovery now is expected, not a setback."
        }
    }
}

/// Simple calendar-based cycle tracking from logged period start dates.
enum CycleTracker {
    static func status(periodStarts: [Date], now: Date = Date()) -> CycleStatus? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let starts = periodStarts.map { cal.startOfDay(for: $0) }.sorted()
        guard let last = starts.last(where: { $0 <= today }) else { return nil }

        var gaps: [Double] = []
        if starts.count >= 2 {
            for i in 1..<starts.count {
                let g = Double(cal.dateComponents([.day], from: starts[i - 1], to: starts[i]).day ?? 0)
                if (21...45).contains(g) { gaps.append(g) }
            }
        }
        let length = Int((Stats.mean(Array(gaps.suffix(6))) ?? 28).rounded())
        let day = (cal.dateComponents([.day], from: last, to: today).day ?? 0) + 1
        let ovulation = length - 14

        let phase: CycleStatus.Phase
        if day <= 5 {
            phase = .menstrual
        } else if day < ovulation - 1 {
            phase = .follicular
        } else if day <= ovulation + 1 {
            phase = .ovulatory
        } else {
            phase = .luteal
        }
        let next = cal.date(byAdding: .day, value: length, to: last) ?? today
        return CycleStatus(day: day, length: length, phase: phase, nextPeriod: next)
    }
}
