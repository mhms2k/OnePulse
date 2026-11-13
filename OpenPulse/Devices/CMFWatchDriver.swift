import Foundation
import CoreBluetooth

/// Talks directly to CMF by Nothing watches (Watch Pro, Watch Pro 2, Watch 3 Pro):
/// pairs without the Nothing X app, authenticates, sets the clock and pulls every
/// recorded sample (heart rate, sleep stages, SpO₂, stress, steps, workouts).
final class CMFWatchDriver: WearableDriver, CBPeripheralDelegate {
    // GATT layout
    static let commandService = CBUUID(string: "FFF0")
    static let commandRead = CBUUID(string: "FFF1")     // notifications from the watch
    static let commandWrite = CBUUID(string: "FFF2")
    static let dataService = CBUUID(string: "02F00000-0000-0000-0000-00000000FFE0")
    static let dataWrite = CBUUID(string: "02F00000-0000-0000-0000-00000000FFE1")
    static let dataRead = CBUUID(string: "02F00000-0000-0000-0000-00000000FFE2")
    static let shellService = CBUUID(string: "77D4E67C-2FE2-2334-0D35-9CCD078F529C")
    static let shellWrite = CBUUID(string: "77D4FF01-2FE2-2334-0D35-9CCD078F529C")
    static let shellRead = CBUUID(string: "77D4FF02-2FE2-2334-0D35-9CCD078F529C")

    override var kind: DeviceKind { .cmfWatch }

    private enum Phase { case discovering, pairing, authenticating, ready }
    private var phase: Phase = .discovering

    private var cmdRead: CBCharacteristic?
    private var cmdWrite: CBCharacteristic?
    private var dataReadChar: CBCharacteristic?
    private var shellReadChar: CBCharacteristic?
    private var shellWriteChar: CBCharacteristic?
    private var pendingServiceDiscoveries = 0
    private var pendingNotifySetups = 0

    private let codec = CMFCodec()
    private var account: String { peripheral.identifier.uuidString }
    private var pairingKey: [UInt8]?
    private var appSecret: [UInt8]?
    private var random1: [UInt8]?
    private var shellBuffer = ""

    private var writeQueue: [(CBCharacteristic, Data)] = []
    private var writeInFlight = false

    private var isSyncing = false
    private var pending = HealthBatch(source: CMFRecords.source)
    private var watchdog: DispatchWorkItem?
    private var periodicSync: Timer?
    var settings = WatchSettings.load()

    // MARK: Lifecycle

    override func start() {
        peripheral.delegate = self
        phase = .discovering
        emit(.status("Discovering services…"))
        peripheral.discoverServices(nil)
    }

    override func stop() {
        periodicSync?.invalidate()
        periodicSync = nil
        watchdog?.cancel()
        if isSyncing { finishSync(reason: "connection lost") }
        codec.reset()
        writeQueue.removeAll()
        writeInFlight = false
    }

    override func sync() {
        guard phase == .ready else {
            emit(.status("Not authenticated yet"))
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        pending = HealthBatch(source: CMFRecords.source)
        emit(.syncStarted)
        emit(.status("Syncing…"))
        send(.activityFetch1, [0xA5])
        armWatchdog()
    }

    override func find() {
        guard phase == .ready else { return }
        send(.findWatch)
    }

    override func apply(_ settings: WatchSettings) {
        self.settings = settings
        guard phase == .ready else { return }
        send(.healthMonitoringSet, [0x01, settings.allDayHeartRate ? 1 : 0])
        send(.healthMonitoringSet, [0x02, settings.spo2Monitoring ? 1 : 0])
        send(.healthMonitoringSet, [0x04, settings.stressMonitoring ? 1 : 0])
    }

    // MARK: Discovery

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { return fail("Service discovery failed: \(error.localizedDescription)") }
        let wanted: Set<CBUUID> = [Self.commandService, Self.dataService, Self.shellService]
        let services = (peripheral.services ?? []).filter { wanted.contains($0.uuid) }
        log(.info, "Services: \((peripheral.services ?? []).map(\.uuid.uuidString).joined(separator: ", "))")
        guard services.contains(where: { $0.uuid == Self.commandService }) else {
            return fail("This device doesn't expose the CMF command service (FFF0).")
        }
        pendingServiceDiscoveries = services.count
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { log(.error, "Characteristic discovery failed: \(error.localizedDescription)") }
        for c in service.characteristics ?? [] {
            switch c.uuid {
            case Self.commandRead: cmdRead = c
            case Self.commandWrite: cmdWrite = c
            case Self.dataRead: dataReadChar = c
            case Self.shellRead: shellReadChar = c
            case Self.shellWrite: shellWriteChar = c
            default: break
            }
        }
        pendingServiceDiscoveries -= 1
        guard pendingServiceDiscoveries <= 0 else { return }

        guard cmdRead != nil, cmdWrite != nil else { return fail("Watch command channel not found.") }
        let notify = [cmdRead, dataReadChar, shellReadChar].compactMap { $0 }
        pendingNotifySetups = notify.count
        for c in notify { peripheral.setNotifyValue(true, for: c) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { log(.error, "Notify \(characteristic.uuid): \(error.localizedDescription)") }
        pendingNotifySetups -= 1
        if pendingNotifySetups <= 0, phase == .discovering { beginAuthentication() }
    }

    // MARK: Authentication

    private func beginAuthentication() {
        codec.mtu = peripheral.maximumWriteValueLength(for: .withoutResponse) + 3
        log(.info, "MTU \(codec.mtu)")
        if let key = Keychain.get(account) {
            phase = .authenticating
            pairingKey = key
            codec.key = key
            emit(.status("Authenticating…"))
            send(.authPhoneName, CMFAuth.phoneNamePayload("iPhone"))
        } else if let shell = shellWriteChar {
            phase = .pairing
            emit(.status("Pairing…"))
            shellBuffer = ""
            write(Array("AT GETSECRET".utf8), to: shell)
            log(.tx, "shell: AT GETSECRET")
        } else {
            fail("The watch didn't offer its pairing channel. Remove it from the Nothing X app and from iPhone Settings › Bluetooth, restart the watch, then try again.")
        }
    }

    private func handleShell(_ text: String) {
        shellBuffer += text
        log(.rx, "shell: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        guard shellBuffer.contains(",OK") || shellBuffer.contains("ERR") else { return }
        defer { shellBuffer = "" }
        guard let secret = CMFAuth.parseSecret(shellResponse: shellBuffer) else {
            return fail("The watch refused to share its pairing secret. Unpair it from Nothing X first.")
        }
        appSecret = secret
        let r1 = CMFCrypto.randomBytes(16)
        random1 = r1
        send(.authPairRequest, CMFAuth.pairRequest(random1: r1, secret: secret))
    }

    private func handle(_ cmd: CMFCommand, _ payload: [UInt8]) {
        switch cmd {
        case .authPairReply:
            guard let r1 = random1, let secret = appSecret,
                  let key = CMFAuth.pairingKey(reply: payload, random1: r1, secret: secret) else {
                return fail("Pairing handshake failed (watch signature mismatch).")
            }
            Keychain.set(key, for: account)
            pairingKey = key
            codec.key = key
            phase = .authenticating
            log(.info, "Paired — key stored in Keychain")
            send(.authPhoneName, CMFAuth.phoneNamePayload("iPhone"))

        case .authWatchMac:
            send(.authNonceRequest, [0xA5])

        case .authNonceReply:
            guard let key = pairingKey else { return fail("Missing pairing key") }
            codec.key = CMFAuth.sessionKey(nonce: payload, pairingKey: key)
            send(.authConfirmRequest, [0xA5])

        case .authConfirmReply:
            phase = .ready
            emit(.status("Connected"))
            emit(.ready)
            afterAuthentication()

        case .authFailed:
            Keychain.remove(account)
            fail("The watch rejected our key. Tap Connect to pair again.")

        case .battery:
            if let b = CMFRecords.battery(payload) { emit(.battery(b.level)) }

        case .firmwareVersionRet:
            emit(.firmware(CMFRecords.firmware(payload)))

        case .serialNumberRet:
            if let s = CMFRecords.serial(payload) { emit(.serial(s)) }

        case .triggerSync:
            sync()

        case .activityFetchAck1:
            switch payload.first ?? 0 {
            case 0x01: send(.activityFetch2, [0xA5]); armWatchdog()
            case 0x02: finishSync(reason: nil)
            default: log(.error, "Unknown fetch ack \(payload.hex)")
            }

        case .activityFetchAck2:
            armWatchdog()

        case .activityData:
            collect { pending.steps += try CMFRecords.activity(payload) }
        case .heartRateAuto, .heartRateWorkout:
            collect { pending.heartRate += try CMFRecords.heartRate(payload) }
        case .heartRateResting:
            pending.restingHeartRate += CMFRecords.restingHeartRate(payload)
        case .sleepData:
            collect { pending.sleep.append(try CMFRecords.sleep(payload)) }
        case .spo2:
            collect { pending.spo2 += try CMFRecords.spo2(payload) }
        case .stress:
            collect { pending.stress += try CMFRecords.stress(payload) }
        case .workoutSummary:
            collect { pending.workouts += try CMFRecords.workouts(payload) }

        default:
            break
        }
    }

    private func collect(_ work: () throws -> Void) {
        do { try work() } catch { log(.error, "Parse error: \(error.localizedDescription)") }
        armWatchdog()
    }

    private func afterAuthentication() {
        send(.time, CMFAuth.timePayload(date: Date()))
        send(.firmwareVersionGet)
        send(.serialNumberGet)
        apply(settings)
        periodicSync?.invalidate()
        periodicSync = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.sync() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.sync() }
    }

    // MARK: Sync bookkeeping

    private func armWatchdog() {
        watchdog?.cancel()
        guard isSyncing else { return }
        let item = DispatchWorkItem { [weak self] in self?.finishSync(reason: "timed out") }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: item)
    }

    private func finishSync(reason: String?) {
        watchdog?.cancel()
        guard isSyncing else { return }
        isSyncing = false
        let batch = pending
        pending = HealthBatch(source: CMFRecords.source)
        log(.info, "Sync done\(reason.map { " (\($0))" } ?? ""): \(batch.summary)")
        emit(.batch(batch))
        emit(.syncFinished)
        emit(.status(reason == nil ? "Synced" : "Synced (\(reason!))"))
    }

    private func fail(_ message: String) {
        log(.error, message)
        emit(.failed(message))
    }

    // MARK: Transport

    private func send(_ cmd: CMFCommand, _ payload: [UInt8] = []) {
        guard let c = cmdWrite else { return }
        do {
            let frames = try codec.encode(cmd, payload: payload)
            let shown = cmd == .authPairRequest ? "<\(payload.count) bytes>" : payload.hex
            log(.tx, "\(cmd) \(shown)")
            for f in frames { write(f, to: c) }
        } catch {
            log(.error, "Encode \(cmd) failed: \(error.localizedDescription)")
        }
    }

    private func write(_ bytes: [UInt8], to c: CBCharacteristic) {
        writeQueue.append((c, Data(bytes)))
        pump()
    }

    private func pump() {
        while !writeInFlight, let next = writeQueue.first {
            let (c, data) = next
            if c.properties.contains(.write) {
                writeQueue.removeFirst()
                writeInFlight = true
                peripheral.writeValue(data, for: c, type: .withResponse)
            } else if peripheral.canSendWriteWithoutResponse {
                writeQueue.removeFirst()
                peripheral.writeValue(data, for: c, type: .withoutResponse)
            } else {
                return // resumed from peripheralIsReady(toSendWriteWithoutResponse:)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { log(.error, "Write failed: \(error.localizedDescription)") }
        writeInFlight = false
        pump()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        pump()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        let bytes = [UInt8](value)

        if characteristic.uuid == Self.shellRead {
            handleShell(String(decoding: bytes, as: UTF8.self))
            return
        }

        switch codec.decode(bytes) {
        case .message(let cmd, let payload):
            log(.rx, "\(cmd) \(payload.count) bytes\(payload.count <= 48 ? ": " + payload.hex : "")")
            handle(cmd, payload)
        case .partial(let cmd, let received, let total):
            if received == 1 { log(.rx, "\(cmd) receiving \(total) chunks…") }
            armWatchdog()
        case .unknown(let c1, let c2, let payload):
            log(.rx, String(format: "unknown %04x/%04x ", c1, c2) + payload.prefix(64).hex)
        case .error(let message):
            log(.error, message)
        }
    }
}
