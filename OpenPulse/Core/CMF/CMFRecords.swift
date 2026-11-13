import Foundation

/// Decoders for the recorded-data messages a CMF watch streams during a sync.
/// All multi-byte fields in these records are little-endian; timestamps are Unix seconds.
enum CMFRecords {
    static let source = "CMF Watch"

    /// 8-byte `(timestamp:u32, value:u32)` records — used for heart rate, SpO2 and stress.
    static func pairs(_ payload: [UInt8]) throws -> [(Date, Int)] {
        guard payload.count % 8 == 0 else { throw ParseError.badLength(payload.count, multipleOf: 8) }
        var r = ByteReader(payload)
        var out: [(Date, Int)] = []
        while !r.isAtEnd {
            let ts = try r.u32LE()
            let value = try r.u32LE()
            out.append((Date(timeIntervalSince1970: TimeInterval(ts)), Int(value)))
        }
        return out.filter { isPlausible($0.0) }
    }

    static func heartRate(_ payload: [UInt8]) throws -> [HRPoint] {
        try pairs(payload).filter { (25...230).contains($0.1) }.map { HRPoint(date: $0.0, bpm: $0.1) }
    }

    static func spo2(_ payload: [UInt8]) throws -> [ValuePoint] {
        try pairs(payload).filter { (70...100).contains($0.1) }.map { ValuePoint(date: $0.0, value: Double($0.1)) }
    }

    static func stress(_ payload: [UInt8]) throws -> [ValuePoint] {
        try pairs(payload).filter { (1...100).contains($0.1) }.map { ValuePoint(date: $0.0, value: Double($0.1)) }
    }

    /// Resting heart rate records are not documented anywhere yet. We try the same
    /// 8-byte layout as the other vitals and only accept values that look like a
    /// resting heart rate; everything is also kept in the raw packet log for decoding.
    static func restingHeartRate(_ payload: [UInt8]) -> [ValuePoint] {
        guard let list = try? pairs(payload) else { return [] }
        return list.filter { (30...110).contains($0.1) }.map { ValuePoint(date: $0.0, value: Double($0.1)) }
    }

    /// 32-byte records: ts, steps, distance (m), calories, then 16 unknown bytes.
    static func activity(_ payload: [UInt8]) throws -> [StepPoint] {
        guard payload.count % 32 == 0 else { throw ParseError.badLength(payload.count, multipleOf: 32) }
        var r = ByteReader(payload)
        var out: [StepPoint] = []
        while !r.isAtEnd {
            let ts = try r.u32LE()
            let steps = try r.u32LE()
            let distance = try r.u32LE()
            let calories = try r.u32LE()
            try r.skip(16)
            let date = Date(timeIntervalSince1970: TimeInterval(ts))
            guard isPlausible(date), steps < 100_000 else { continue }
            out.append(StepPoint(date: date, steps: Int(steps), distance: Int(distance), calories: Int(calories)))
        }
        return out
    }

    /// One sleep session: start:u32, wake:u32, 10 bytes metadata, then
    /// 8-byte stage segments `(start:u32, durationSeconds:u16, stage:u16)`.
    /// Stage codes: 1 = deep, 2 = light, 3 = REM, anything else = awake.
    static func sleep(_ payload: [UInt8]) throws -> SleepRecord {
        var r = ByteReader(payload)
        let start = Date(timeIntervalSince1970: TimeInterval(try r.u32LE()))
        let end = Date(timeIntervalSince1970: TimeInterval(try r.u32LE()))
        try r.skip(10)
        var segments: [SleepSegment] = []
        while r.remaining >= 8 {
            let ts = try r.u32LE()
            let duration = try r.u16LE()
            let code = try r.u16LE()
            let stage: SleepStage
            switch code {
            case 1: stage = .deep
            case 2: stage = .light
            case 3: stage = .rem
            default: stage = .awake
            }
            segments.append(SleepSegment(start: Date(timeIntervalSince1970: TimeInterval(ts)),
                                         duration: TimeInterval(duration), stage: stage))
        }
        guard isPlausible(start), end > start, end.timeIntervalSince(start) < 20 * 3600 else {
            throw ParseError.implausible("sleep session \(start) – \(end)")
        }
        return SleepRecord(start: start, end: end, segments: segments.sorted { $0.start < $1.start }, source: source)
    }

    /// Workout summaries come as 32- or 54-byte records:
    /// start:u32, duration:u16, type:u8, 19 unknown bytes, end:u32, gps:u8, …
    static func workouts(_ payload: [UInt8]) throws -> [WorkoutRecord] {
        let size: Int
        if payload.count % 32 == 0 { size = 32 } else if payload.count % 54 == 0 { size = 54 } else {
            throw ParseError.badLength(payload.count, multipleOf: 32)
        }
        var out: [WorkoutRecord] = []
        var offset = 0
        while offset + size <= payload.count {
            var r = ByteReader(Array(payload[offset..<(offset + size)]))
            offset += size
            let start = Date(timeIntervalSince1970: TimeInterval(try r.u32LE()))
            _ = try r.u16LE()
            let type = try r.u8()
            try r.skip(19)
            let end = Date(timeIntervalSince1970: TimeInterval(try r.u32LE()))
            guard isPlausible(start), end > start else { continue }
            out.append(WorkoutRecord(start: start, end: end, activity: activityName(type), source: source))
        }
        return out
    }

    static func battery(_ payload: [UInt8]) -> (level: Int, charging: Bool)? {
        guard payload.count >= 2 else { return nil }
        return (Int(payload[0]), payload[1] == 0x01)
    }

    static func firmware(_ payload: [UInt8]) -> String {
        payload.map { String($0) }.joined(separator: ".")
    }

    static func serial(_ payload: [UInt8]) -> String? {
        guard let len = payload.first, payload.count == Int(len) + 1 else { return nil }
        return String(decoding: payload.dropFirst(), as: UTF8.self)
    }

    /// Rejects obviously wrong timestamps (unset watch clock, corrupt data).
    static func isPlausible(_ date: Date) -> Bool {
        date.timeIntervalSince1970 > 1_577_836_800 && date < Date().addingTimeInterval(86_400)
    }

    static func activityName(_ code: UInt8) -> String {
        switch code {
        case 0x01: return "Outdoor Walk"
        case 0x02: return "Outdoor Run"
        case 0x03: return "Indoor Run"
        case 0x04: return "Mountain Hike"
        case 0x05: return "Outdoor Cycle"
        case 0x06: return "Jump Rope"
        case 0x0D: return "Dynamic Cycle"
        case 0x0E: return "Rowing"
        case 0x0F: return "Yoga"
        case 0x10: return "Free Training"
        case 0x13: return "Strength Training"
        case 0x18: return "Elliptical"
        case 0x19: return "Indoor Walk"
        case 0x1A: return "Hiking"
        case 0x1B: return "Trail Run"
        case 0x21: return "Boxing"
        case 0x26: return "Treadmill"
        case 0x2C: return "Pilates"
        case 0x2E: return "Functional Training"
        case 0x35: return "Kickboxing"
        case 0x4E: return "Fitness"
        case 0x5C: return "HIIT"
        case 0x72: return "Indoor Cycle"
        case 0x73: return "Stair Stepper"
        case 0x74: return "CrossFit"
        default: return "Workout"
        }
    }

    enum ParseError: Error, LocalizedError {
        case badLength(Int, multipleOf: Int)
        case implausible(String)
        var errorDescription: String? {
            switch self {
            case .badLength(let n, let m): return "Payload of \(n) bytes is not a multiple of \(m)"
            case .implausible(let s): return "Implausible \(s)"
            }
        }
    }
}
