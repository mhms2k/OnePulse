import Foundation

/// A command understood by CMF / Nothing watches (Watch Pro, Watch Pro 2, Watch 3 Pro).
///
/// Every message carries two 16-bit codes. The table below was derived from the
/// open protocol notes in the Gadgetbridge project (AGPL); this file is an
/// independent Swift description of that protocol, not a copy of its code.
struct CMFCommand: Hashable, CustomStringConvertible {
    let cmd1: UInt16
    let cmd2: UInt16
    let name: String

    init(_ cmd1: UInt16, _ cmd2: UInt16, _ name: String) {
        self.cmd1 = cmd1
        self.cmd2 = cmd2
        self.name = name
    }

    var description: String { name }

    /// Pairing messages travel in plaintext; everything else is AES encrypted.
    var isEncrypted: Bool { self != .authPairRequest && self != .authPairReply }

    // MARK: Authentication
    static let authPairRequest       = CMFCommand(0xffff, 0x8047, "AUTH_PAIR_REQUEST")
    static let authPairReply         = CMFCommand(0xffff, 0x0048, "AUTH_PAIR_REPLY")
    static let authPhoneName         = CMFCommand(0xffff, 0x8049, "AUTH_PHONE_NAME")
    static let authWatchMac          = CMFCommand(0xffff, 0x0049, "AUTH_WATCH_MAC")
    static let authNonceRequest      = CMFCommand(0xffff, 0x804b, "AUTH_NONCE_REQUEST")
    static let authNonceReply        = CMFCommand(0xffff, 0x004c, "AUTH_NONCE_REPLY")
    static let authConfirmRequest    = CMFCommand(0xffff, 0x804d, "AUTH_CONFIRM_REQUEST")
    static let authConfirmReply      = CMFCommand(0xffff, 0x0004, "AUTH_CONFIRM_REPLY")
    static let authFailed            = CMFCommand(0xffff, 0xa061, "AUTH_FAILED")

    // MARK: Device info
    static let time                  = CMFCommand(0xffff, 0x8004, "TIME")
    static let firmwareVersionGet    = CMFCommand(0xffff, 0x8006, "FIRMWARE_VERSION_GET")
    static let firmwareVersionRet    = CMFCommand(0xffff, 0x0006, "FIRMWARE_VERSION_RET")
    static let serialNumberGet       = CMFCommand(0x00de, 0x0002, "SERIAL_NUMBER_GET")
    static let serialNumberRet       = CMFCommand(0x00de, 0x0001, "SERIAL_NUMBER_RET")
    static let battery               = CMFCommand(0x005c, 0x0001, "BATTERY")
    static let triggerSync           = CMFCommand(0x005c, 0x0002, "TRIGGER_SYNC")
    static let findWatch             = CMFCommand(0x005d, 0x0001, "FIND_WATCH")
    static let findPhone             = CMFCommand(0x005b, 0x0001, "FIND_PHONE")

    // MARK: Health monitoring settings
    /// Payload `[type, enabled]` — type 1 = all-day heart rate, 2 = SpO2, 4 = stress.
    static let healthMonitoringSet   = CMFCommand(0x009b, 0x0001, "HEALTH_MONITORING_SET")
    static let healthMonitoringGet   = CMFCommand(0x009b, 0x0002, "HEALTH_MONITORING_GET")

    // MARK: Recorded data sync
    static let activityFetch1        = CMFCommand(0xffff, 0x8005, "ACTIVITY_FETCH_1")
    static let activityFetchAck1     = CMFCommand(0xffff, 0x0005, "ACTIVITY_FETCH_ACK_1")
    static let activityFetch2        = CMFCommand(0xffff, 0x9057, "ACTIVITY_FETCH_2")
    static let activityFetchAck2     = CMFCommand(0xffff, 0xa057, "ACTIVITY_FETCH_ACK_2")
    static let activityData          = CMFCommand(0x0056, 0x0001, "ACTIVITY_DATA")
    static let heartRateAuto         = CMFCommand(0x0053, 0x0001, "HEART_RATE_AUTO")
    static let heartRateWorkout      = CMFCommand(0x00e0, 0x0001, "HEART_RATE_WORKOUT")
    static let heartRateResting      = CMFCommand(0x00da, 0x0001, "HEART_RATE_RESTING")
    static let sleepData             = CMFCommand(0x0058, 0x0001, "SLEEP_DATA")
    static let spo2                  = CMFCommand(0x0055, 0x0001, "SPO2")
    static let stress                = CMFCommand(0x009d, 0x0001, "STRESS")
    static let workoutSummary        = CMFCommand(0x0057, 0x0001, "WORKOUT_SUMMARY")
    static let workoutGPS            = CMFCommand(0xffff, 0xa05a, "WORKOUT_GPS")

    static let all: [CMFCommand] = [
        .authPairRequest, .authPairReply, .authPhoneName, .authWatchMac, .authNonceRequest,
        .authNonceReply, .authConfirmRequest, .authConfirmReply, .authFailed,
        .time, .firmwareVersionGet, .firmwareVersionRet, .serialNumberGet, .serialNumberRet,
        .battery, .triggerSync, .findWatch, .findPhone,
        .healthMonitoringSet, .healthMonitoringGet,
        .activityFetch1, .activityFetchAck1, .activityFetch2, .activityFetchAck2, .activityData,
        .heartRateAuto, .heartRateWorkout, .heartRateResting, .sleepData, .spo2, .stress,
        .workoutSummary, .workoutGPS,
    ]

    private static let lookup: [UInt32: CMFCommand] = {
        var map: [UInt32: CMFCommand] = [:]
        for c in all { map[UInt32(c.cmd1) << 16 | UInt32(c.cmd2)] = c }
        return map
    }()

    static func from(_ cmd1: UInt16, _ cmd2: UInt16) -> CMFCommand? {
        lookup[UInt32(cmd1) << 16 | UInt32(cmd2)]
    }
}
