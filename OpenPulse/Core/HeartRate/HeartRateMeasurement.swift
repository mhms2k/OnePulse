import Foundation

/// Bluetooth SIG Heart Rate Measurement characteristic (0x2A37).
/// Works with any standard chest strap, armband or watch in "broadcast HR" mode
/// (Polar, Garmin, Wahoo, Coros, Suunto, Amazfit, …).
struct HeartRateMeasurement: Equatable {
    var bpm: Int
    var sensorContact: Bool?
    var energyExpended: Int?
    /// Beat-to-beat intervals in milliseconds (needed for true HRV).
    var rrIntervals: [Double]

    init(bpm: Int, sensorContact: Bool? = nil, energyExpended: Int? = nil, rrIntervals: [Double] = []) {
        self.bpm = bpm
        self.sensorContact = sensorContact
        self.energyExpended = energyExpended
        self.rrIntervals = rrIntervals
    }

    init?(_ data: [UInt8]) {
        var r = ByteReader(data)
        guard let flags = try? r.u8() else { return nil }
        let is16Bit = flags & 0x01 != 0
        let contactSupported = flags & 0x04 != 0
        let contactDetected = flags & 0x02 != 0
        let hasEnergy = flags & 0x08 != 0
        let hasRR = flags & 0x10 != 0

        do {
            bpm = try is16Bit ? Int(r.u16LE()) : Int(r.u8())
            sensorContact = contactSupported ? contactDetected : nil
            energyExpended = try hasEnergy ? Int(r.u16LE()) : nil
            var rr: [Double] = []
            if hasRR {
                while r.remaining >= 2 {
                    let raw = try r.u16LE()
                    rr.append(Double(raw) / 1024.0 * 1000.0)
                }
            }
            rrIntervals = rr
        } catch {
            return nil
        }
    }
}

/// Heart rate variability from RR intervals.
enum HRVCalculator {
    /// Removes artefacts: physiologically impossible intervals and beats that differ
    /// more than 20% from the previous accepted beat (ectopic / missed beats).
    static func clean(_ rr: [Double]) -> [Double] {
        var out: [Double] = []
        for v in rr where (300...2000).contains(v) {
            if let last = out.last, abs(v - last) / last > 0.2 { continue }
            out.append(v)
        }
        return out
    }

    /// Root mean square of successive differences, in milliseconds.
    static func rmssd(_ rr: [Double]) -> Double? {
        let c = clean(rr)
        guard c.count >= 10 else { return nil }
        var sum = 0.0
        for i in 1..<c.count {
            let d = c[i] - c[i - 1]
            sum += d * d
        }
        return (sum / Double(c.count - 1)).squareRoot()
    }
}

/// Collects live RR intervals and emits one RMSSD value per window.
struct RRWindowAccumulator {
    var windowSeconds: TimeInterval = 60
    private(set) var windowStart: Date?
    private var buffer: [Double] = []

    init(windowSeconds: TimeInterval = 60) { self.windowSeconds = windowSeconds }

    /// Adds intervals; returns a finished HRV point when the window closes.
    mutating func add(_ rr: [Double], at date: Date) -> ValuePoint? {
        if windowStart == nil { windowStart = date }
        buffer.append(contentsOf: rr)
        guard let start = windowStart, date.timeIntervalSince(start) >= windowSeconds else { return nil }
        defer { windowStart = nil; buffer.removeAll() }
        guard let value = HRVCalculator.rmssd(buffer) else { return nil }
        return ValuePoint(date: start, value: value)
    }
}
