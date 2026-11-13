import Foundation

enum Stats {
    static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    static func sd(_ xs: [Double]) -> Double? {
        guard xs.count >= 2, let m = mean(xs) else { return nil }
        let v = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)
        return v.squareRoot()
    }

    static func median(_ xs: [Double]) -> Double? { percentile(xs, 0.5) }

    /// Linear-interpolated percentile, p in 0...1.
    static func percentile(_ xs: [Double], _ p: Double) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let pos = p * Double(s.count - 1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        if lo == hi { return s[lo] }
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }

    static func clamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T { min(max(x, lo), hi) }

    static func logistic(_ x: Double) -> Double { 1 / (1 + exp(-x)) }
}

/// Personal baseline of a metric: mean and spread over a trailing window.
struct Baseline: Codable, Hashable {
    var mean: Double
    var sd: Double
    var count: Int

    init?(_ values: [Double], minCount: Int = 4, sdFloor: Double) {
        guard values.count >= minCount, let m = Stats.mean(values) else { return nil }
        mean = m
        sd = max(Stats.sd(values) ?? sdFloor, sdFloor)
        count = values.count
    }

    func z(_ x: Double) -> Double { (x - mean) / sd }
}
