import XCTest
@testable import OpenPulse

/// Test vectors were produced by an independent Python implementation of the CMF
/// protocol (pycryptodome AES-CBC + zlib CRC32), so these tests check the Swift code
/// against a second implementation rather than against itself.
final class CMFProtocolTests: XCTestCase {
    let key = Array<UInt8>(0..<16)

    func testCRC32MatchesZlib() {
        XCTAssertEqual(CRC32.checksum(Array("123456789".utf8)), 0xCBF43926)
    }

    func testTimePayload() {
        let tz = TimeZone(secondsFromGMT: 3 * 3600)!
        let payload = CMFAuth.timePayload(date: Date(timeIntervalSince1970: 1_700_000_000), timeZone: tz)
        XCTAssertEqual(payload.hex, "6553f10000a4cb80")
    }

    func testEncryptedFrameMatchesReference() throws {
        let codec = CMFCodec(key: key, mtu: 247)
        let frames = try codec.encode(.time, payload: [UInt8](hex: "6553f10000a4cb80")!)
        XCTAssertEqual(frames.map { $0.hex }, ["f50010ffff000100018004cee82eef89cc14acb5738729af380a13"])
    }

    func testEmptyEncryptedCommand() throws {
        let codec = CMFCodec(key: key, mtu: 247)
        XCTAssertEqual(try codec.encode(.firmwareVersionGet).map { $0.hex }, ["f50000ffff000100018006"])
    }

    func testPairRequestIsPlaintextWithCRC() throws {
        let random1 = [UInt8](repeating: 0x11, count: 16)
        let secret = [UInt8](hex: "00112233445566778899aabbccddeeff")!
        let payload = CMFAuth.pairRequest(random1: random1, secret: secret)
        XCTAssertEqual(payload.hex, "11111111111111111111111111111111bcb1a14a3772482975915c061a03dc6d0b462c9ec6361ba6cadece39f6da1ca6")
        let codec = CMFCodec(key: nil, mtu: 247) // no key needed for pairing frames
        XCTAssertEqual(try codec.encode(.authPairRequest, payload: payload).map { $0.hex }, ["f50034ffff00010001804711111111111111111111111111111111bcb1a14a3772482975915c061a03dc6d0b462c9ec6361ba6cadece39f6da1ca6eff3d324"])
    }

    func testPairingAndSessionKeyDerivation() {
        let random1 = [UInt8](repeating: 0x11, count: 16)
        let secret = [UInt8](hex: "00112233445566778899aabbccddeeff")!
        let reply = [UInt8](hex: "22222222222222222222222222222222c71081d94b614c618ee10e2f7a9ca8c4cc6ef0ef3ee4a71347db3e2594999600")!
        let pairingKey = CMFAuth.pairingKey(reply: reply, random1: random1, secret: secret)
        XCTAssertEqual(pairingKey?.hex, "c6f906fb1d15e1830010450af8fc95c6")

        var forged = reply
        forged[20] ^= 0xFF
        XCTAssertNil(CMFAuth.pairingKey(reply: forged, random1: random1, secret: secret), "a bad watch signature must be rejected")

        let session = CMFAuth.sessionKey(nonce: [UInt8](hex: "a1b2c3d4e5f60718")!, pairingKey: pairingKey ?? [])
        XCTAssertEqual(session.hex, "d81ebf4675248cf6cda6fcc4f399bcc1")
    }

    func testParseShellSecret() {
        XCTAssertEqual(CMFAuth.parseSecret(shellResponse: "GETSECRET:00112233445566778899AABBCCDDEEFF,OK\r\n")?.hex,
                       "00112233445566778899aabbccddeeff")
        XCTAssertNil(CMFAuth.parseSecret(shellResponse: "GETSECRET:ERROR"))
    }

    func testMultiChunkHeartRateMessage() throws {
        let codec = CMFCodec(key: key)
        let frames = [
            "f5005000530005000100011c8cca80e8de7ba40e27abe8cfc5ba70960e86d0afc4070b7928bb321a42a3a039251920d7e0238dd7f1fb5e5864d5e860566333eb6f97c906198cd8550c575c252e4188b169297b7f9b0154c7cb30df",
            "f500500053000500020001f866dbc52e630ee722a6f1dc6677d8af4ec19cf44e35ac0fb254c8cf844ef90c4a82b7762194630a977a5f376c280d1f002180d9b2436f2ff33a296802e67537ba9c8f18a75d97ef113f9256eb530d2c",
            "f5005000530005000300015bd5d05ffb02ba18deb4af578cee15085f8a24ab09a345befbd89574ddfd1bcfec74928e15e81aa4c269930895c8e26726a3495504d2aff09311faf7855c3ced029f8170880228577ae0923dc72c6fd9",
            "f500500053000500040001bed804c1a53c8b5b28d10ade8940c5792cdb9f97f3854fed1b06e0eb573d645fc3bd89cc60e8d96c8937d086e422e43e285cabb761e8cfecc47b504b688166fa0c0ef86b3d03f5976a3bc7866d195f3c",
            "f50020005300050005000163e5ebb56ea9a71c1b9a69142264ef517097b8c7faf88faa7012a96b857a3c91"
        ].map { [UInt8](hex: $0)! }

        for f in frames.dropLast() {
            guard case .partial(let cmd, _, let total) = codec.decode(f) else { return XCTFail("expected partial chunk") }
            XCTAssertEqual(cmd, .heartRateAuto)
            XCTAssertEqual(total, 5)
        }
        guard case .message(let cmd, let payload) = codec.decode(frames.last!) else { return XCTFail("expected full message") }
        XCTAssertEqual(cmd, .heartRateAuto)
        let samples = try CMFRecords.heartRate(payload)
        XCTAssertEqual(samples.count, 40)
        XCTAssertEqual(samples.first?.bpm, 50)
        XCTAssertEqual(samples.last?.bpm, 89)
        XCTAssertEqual(samples.first?.date, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testEncodeDecodeRoundTrip() throws {
        let codec = CMFCodec(key: key, mtu: 185)
        let payload = (0..<500).map { UInt8($0 % 251) }
        var result: CMFCodec.Inbound?
        for frame in try codec.encode(.stress, payload: payload) { result = codec.decode(frame) }
        XCTAssertEqual(result, .message(.stress, payload))
    }

    func testCorruptFrameIsRejected() throws {
        let codec = CMFCodec(key: key)
        var frame = try codec.encode(.spo2, payload: [1, 2, 3, 4, 5, 6, 7, 8])[0]
        frame[frame.count - 1] ^= 0x55
        if case .message = codec.decode(frame) { XCTFail("corrupted frame must not decode") }
    }

    func testSleepRecordParsing() throws {
        let record = try CMFRecords.sleep([UInt8](hex: "00f15365705354650000000000000000000058f353650807020060fa5365100e010070085465b0040300200d54652c010400")!)
        XCTAssertEqual(record.timeInBed, 7 * 3600)
        XCTAssertEqual(record.segments.map(\.stage), [.light, .deep, .rem, .awake])
        XCTAssertEqual(record.time(in: .deep), 3600)
        XCTAssertEqual(record.asleep, 1800 + 3600 + 1200)
    }
}

final class HeartRateMeasurementTests: XCTestCase {
    func testUInt8HeartRateWithRRIntervals() {
        // flags: RR present (0x10); HR 72; RR 1024/1024 s and 512/1024 s
        let m = HeartRateMeasurement([0x10, 72, 0x00, 0x04, 0x00, 0x02])
        XCTAssertEqual(m?.bpm, 72)
        XCTAssertEqual(m?.rrIntervals, [1000, 500])
        XCTAssertNil(m?.sensorContact)
    }

    func testUInt16HeartRateWithContactAndEnergy() {
        // flags: 16-bit HR, contact supported + detected, energy present
        let m = HeartRateMeasurement([UInt8(0x01 | 0x02 | 0x04 | 0x08), 0x2C, 0x01, 0x10, 0x00])
        XCTAssertEqual(m?.bpm, 300)
        XCTAssertEqual(m?.sensorContact, true)
        XCTAssertEqual(m?.energyExpended, 16)
    }

    func testRMSSD() {
        let rr: [Double] = [1000, 1010, 1000, 1010, 1000, 1010, 1000, 1010, 1000, 1010, 1000]
        XCTAssertEqual(HRVCalculator.rmssd(rr) ?? 0, 10, accuracy: 0.001)
        XCTAssertNil(HRVCalculator.rmssd([1000, 1010]), "too few beats")
    }

    func testArtefactsAreRemoved() {
        let clean = HRVCalculator.clean([1000, 1005, 400, 1010, 2500, 1000])
        XCTAssertEqual(clean, [1000, 1005, 1010, 1000])
    }
}

final class ScoreEngineTests: XCTestCase {
    func testStrainScaleIsMonotonicAndBounded() {
        var previous = -1.0
        for trimp in stride(from: 0.0, through: 2000, by: 50) {
            let s = ScoreEngine.strain(fromTRIMP: trimp)
            XCTAssertGreaterThanOrEqual(s, previous)
            XCTAssertLessThanOrEqual(s, 21)
            previous = s
        }
        XCTAssertEqual(ScoreEngine.strain(fromTRIMP: 0), 0)
    }

    func testHarderEffortMeansMoreStrain() {
        let engine = ScoreEngine(profile: UserProfile())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func session(_ bpm: Int) -> [HRPoint] { (0..<60).map { HRPoint(date: start.addingTimeInterval(Double($0) * 60), bpm: bpm) } }
        let easy = engine.strainLoad(session(115), restingHR: 55).trimp
        let hard = engine.strainLoad(session(165), restingHR: 55).trimp
        let resting = engine.strainLoad(session(62), restingHR: 55).trimp
        XCTAssertEqual(resting, 0, "sitting still should add no strain")
        XCTAssertGreaterThan(hard, easy * 2)
    }

    func testRecoveryWaitsForCalibration() {
        let engine = ScoreEngine(profile: UserProfile())
        var input = DayInput(day: Date())
        input.sleepHeartRate = (0..<20).map { HRPoint(date: Date().addingTimeInterval(Double($0) * 300), bpm: 52) }
        let score = engine.score(input, history: [])
        XCTAssertNil(score.recovery)
        XCTAssertTrue(score.isCalibrating)
        XCTAssertEqual(score.nightsUntilCalibrated, 4)
    }

    func testSleepNeedIncludesStrainAndDebt() {
        var profile = UserProfile()
        profile.baselineSleepHours = 8
        let engine = ScoreEngine(profile: profile)
        var yesterday = DayScore(day: Date())
        yesterday.strain = 21
        yesterday.timeInBed = 6 * 3600
        yesterday.asleep = 6 * 3600
        yesterday.sleepNeed = 8 * 3600
        yesterday.sleepNeedBaseline = 8 * 3600
        let need = engine.sleepNeed(after: yesterday, priorNights: [])
        XCTAssertEqual(need.strain, 50 * 60, accuracy: 1)
        XCTAssertEqual(need.debt, 3600, accuracy: 1) // half of a 2 h shortfall
        XCTAssertEqual(need.total, 8 * 3600 + 50 * 60 + 3600, accuracy: 1)
    }

    @MainActor
    func testDemoDataProducesSensibleScores() {
        let store = HealthStore(inMemory: true)
        store.loadDemoData()
        XCTAssertGreaterThanOrEqual(store.scores.count, 40)
        let recent = store.scores.suffix(20)
        XCTAssertTrue(recent.contains { $0.recovery != nil }, "recovery should unlock after calibration")
        for s in store.scores {
            if let r = s.recovery { XCTAssertTrue((1...99).contains(r)) }
            XCTAssertTrue((0...21).contains(s.strain))
            if let p = s.sleepPerformance { XCTAssertTrue((0...100).contains(p)) }
        }
        let coach = store.coach
        if let today = store.scores.last(where: { $0.hasSleep }) {
            XCTAssertFalse(coach.insights(today: today, history: store.history(before: today.day)).isEmpty)
        }
    }

    func testDayScoreCodableRoundTrip() throws {
        var s = DayScore(day: Date(timeIntervalSince1970: 1_700_000_000))
        s.recovery = 72
        s.rhrBaseline = Baseline([50, 52, 51, 53], sdFloor: 1)
        let decoded = try JSONDecoder().decode(DayScore.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }
}

final class LifestyleFeatureTests: XCTestCase {
    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: Date()))!
    }

    func testBehaviorInsightNeedsFiveOfEach() {
        var scores: [DayScore] = []
        var journal: [Date: [String: Bool]] = [:]
        for i in 0..<12 {
            var s = DayScore(day: day(i))
            let drank = i % 2 == 0
            s.recovery = drank ? 40 : 70
            scores.append(s)
            journal[day(i)] = ["alcohol": drank]
        }
        let insights = BehaviorAnalyzer.insights(journal: journal, scores: scores)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights.first?.behavior.id, "alcohol")
        XCTAssertEqual(insights.first?.impact ?? 0, -30, accuracy: 0.001)

        let fewer = journal.filter { $0.key >= day(5) }
        XCTAssertTrue(BehaviorAnalyzer.insights(journal: fewer, scores: scores).isEmpty, "only 3 of each answer")
    }

    func testHealthspanRewardsGoodHabits() {
        var profile = UserProfile()
        profile.age = 40
        func days(rhr: Double, sleepHours: Double, steps: Int, zone2: Double) -> [DayScore] {
            (0..<20).map { i in
                var s = DayScore(day: day(i))
                s.restingHR = rhr
                s.timeInBed = sleepHours * 3600 + 1800
                s.asleep = sleepHours * 3600
                s.consistency = 85
                s.steps = steps
                s.avgHR = 70
                s.zoneMinutes = [zone2, zone2, 0, 3, 1]
                return s
            }
        }
        let fit = Healthspan.compute(scores: days(rhr: 50, sleepHours: 8, steps: 11000, zone2: 25), strength: [], profile: profile)
        let unfit = Healthspan.compute(scores: days(rhr: 78, sleepHours: 5.5, steps: 3000, zone2: 2), strength: [], profile: profile)
        XCTAssertNotNil(fit)
        XCTAssertNotNil(unfit)
        XCTAssertLessThan(fit!.bodyAge, 40)
        XCTAssertGreaterThan(unfit!.bodyAge, 40)
        XCTAssertLessThan(fit!.paceOfAging, 1)
        XCTAssertGreaterThan(unfit!.paceOfAging, 1)
        XCTAssertNil(Healthspan.compute(scores: Array(days(rhr: 50, sleepHours: 8, steps: 9000, zone2: 20).prefix(5)),
                                        strength: [], profile: profile), "needs two weeks")
    }

    func testStressFromHeartRate() {
        XCTAssertEqual(StressMonitor.fromHeartRate(60, restingHR: 60, asleep: false), 0)
        let moderate = StressMonitor.fromHeartRate(80, restingHR: 60, asleep: false)
        let high = StressMonitor.fromHeartRate(100, restingHR: 60, asleep: false)
        XCTAssertGreaterThan(moderate, 0)
        XCTAssertGreaterThan(high, moderate)
        XCTAssertEqual(StressMonitor.fromHeartRate(200, restingHR: 60, asleep: false), 3)
        XCTAssertEqual(StressMonitor.fromWatchIndex(100), 3)
    }

    func testCyclePhase() {
        let starts = [day(56), day(28), day(0)]
        let today = CycleTracker.status(periodStarts: starts)
        XCTAssertEqual(today?.day, 1)
        XCTAssertEqual(today?.length, 28)
        XCTAssertEqual(today?.phase, .menstrual)
        let later = CycleTracker.status(periodStarts: [day(20)])
        XCTAssertEqual(later?.phase, .luteal)
    }

    func testStrengthRecords() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let w = StrengthWorkout(name: "A", start: start, end: start.addingTimeInterval(3600),
                                sets: [StrengthSet(exercise: "Squat", reps: 5, weightKg: 100),
                                       StrengthSet(exercise: "Squat", reps: 1, weightKg: 120)])
        let r = StrengthStats.records([w])
        XCTAssertEqual(r.first?.bestWeight, 120)
        XCTAssertEqual(r.first?.totalVolume, 620)
        XCTAssertEqual(r.first?.bestOneRepMax ?? 0, 120, accuracy: 0.01)
        XCTAssertEqual(w.duration, 3600)
    }

    @MainActor
    func testDemoJournalProducesAlcoholInsight() {
        let store = HealthStore(inMemory: true)
        store.loadDemoData()
        XCTAssertFalse(store.journal.isEmpty)
        XCTAssertFalse(store.strengthWorkouts.isEmpty)
        let alcohol = store.behaviorInsights.first { $0.behavior.id == "alcohol" }
        XCTAssertNotNil(alcohol)
        XCTAssertLessThan(alcohol?.impact ?? 0, 0, "demo nights with alcohol have lower recovery")
        XCTAssertNotNil(store.healthspan)
    }
}
