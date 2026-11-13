import Foundation
import CoreBluetooth
import Combine

/// Finds, pairs and keeps connections to wearables, routing each to the right driver.
final class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    struct Discovered: Identifiable, Equatable {
        var id: UUID { peripheral.identifier }
        let peripheral: CBPeripheral
        var name: String
        var rssi: Int
        var kind: DeviceKind?
        var alreadyConnected: Bool
    }

    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var discovered: [Discovered] = []
    @Published private(set) var devices: [KnownDevice] = KnownDevice.loadAll()
    @Published private(set) var status: [UUID: String] = [:]
    @Published private(set) var connected: Set<UUID> = []
    @Published private(set) var syncing: Set<UUID> = []
    @Published private(set) var liveHeartRate: Int?
    @Published private(set) var log: [LogLine] = []
    @Published var showAllDevices = false
    @Published var watchSettings = WatchSettings.load() {
        didSet {
            watchSettings.save()
            drivers.values.forEach { $0.apply(watchSettings) }
        }
    }

    /// Called on the main queue whenever a driver produces new data.
    var onBatch: ((HealthBatch) -> Void)?

    private var central: CBCentralManager!
    private var drivers: [UUID: WearableDriver] = [:]
    private var pendingKinds: [UUID: DeviceKind] = [:]
    private var scanStopWork: DispatchWorkItem?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "openpulse.central",
            CBCentralManagerOptionShowPowerAlertKey: true,
        ])
    }

    var isPoweredOn: Bool { bluetoothState == .poweredOn }
    var hasDevices: Bool { !devices.isEmpty }
    var primaryDevice: KnownDevice? { devices.first }
    var isAnySyncing: Bool { !syncing.isEmpty }
    var lastSync: Date? { devices.compactMap(\.lastSync).max() }

    // MARK: Scanning

    func startScan() {
        guard isPoweredOn else { return }
        discovered = []
        // Watches already linked to the iPhone (e.g. for notifications) don't advertise; list them too.
        let linked = central.retrieveConnectedPeripherals(withServices: [CMFWatchDriver.commandService, HeartRateSensorDriver.hrService])
        for p in linked {
            let name = p.name ?? "Unknown device"
            discovered.append(Discovered(peripheral: p, name: name, rssi: 0,
                                         kind: classify(name: name, services: []) ?? .cmfWatch, alreadyConnected: true))
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
        scanStopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stopScan() }
        scanStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    private func classify(name: String, services: [CBUUID]) -> DeviceKind? {
        let n = name.lowercased()
        if services.contains(CMFWatchDriver.commandService) || n.contains("cmf") || n.contains("watch pro")
            || n.contains("nothing") { return .cmfWatch }
        if services.contains(HeartRateSensorDriver.hrService) { return .heartRateSensor }
        let hrNames = ["polar", "h10", "h9", "verity", "hrm", "tickr", "wahoo", "heart", "coospo", "garmin", "magene", "whoop", "amazfit"]
        if hrNames.contains(where: { n.contains($0) }) { return .heartRateSensor }
        return nil
    }

    // MARK: Connecting

    func connect(_ d: Discovered, as kind: DeviceKind) {
        stopScan()
        connect(d.peripheral, kind: kind)
    }

    private func connect(_ p: CBPeripheral, kind: DeviceKind) {
        pendingKinds[p.identifier] = kind
        status[p.identifier] = "Connecting…"
        central.connect(p, options: nil)
    }

    func reconnect(_ device: KnownDevice) {
        guard isPoweredOn, let p = central.retrievePeripherals(withIdentifiers: [device.id]).first else { return }
        connect(p, kind: device.kind)
    }

    private func reconnectKnownDevices() {
        for d in devices where d.autoConnect && !connected.contains(d.id) { reconnect(d) }
    }

    func disconnect(_ device: KnownDevice) {
        if let p = central.retrievePeripherals(withIdentifiers: [device.id]).first {
            central.cancelPeripheralConnection(p)
        }
        update(device.id) { $0.autoConnect = false }
    }

    func forget(_ device: KnownDevice) {
        disconnect(device)
        Keychain.remove(device.id.uuidString)
        drivers[device.id] = nil
        devices.removeAll { $0.id == device.id }
        KnownDevice.saveAll(devices)
        status[device.id] = nil
    }

    func sync(_ device: KnownDevice? = nil) {
        if let device {
            if connected.contains(device.id) { drivers[device.id]?.sync() } else { update(device.id) { $0.autoConnect = true }; reconnect(device) }
        } else {
            for d in devices {
                if connected.contains(d.id) { drivers[d.id]?.sync() } else if d.autoConnect { reconnect(d) }
            }
        }
    }

    func find(_ device: KnownDevice) { drivers[device.id]?.find() }

    func clearLog() { log.removeAll() }

    var logText: String { log.map(\.formatted).joined(separator: "\n") }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state == .poweredOn { reconnectKnownDevices() }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for p in restored {
            if let known = devices.first(where: { $0.id == p.identifier }) { pendingKinds[p.identifier] = known.kind }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let name = peripheral.name ?? advName else { return }
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let kind = classify(name: name, services: services)
        guard kind != nil || showAllDevices else { return }

        let entry = Discovered(peripheral: peripheral, name: name, rssi: RSSI.intValue, kind: kind, alreadyConnected: false)
        if let i = discovered.firstIndex(where: { $0.id == entry.id }) {
            discovered[i].rssi = entry.rssi
        } else {
            discovered.append(entry)
            discovered.sort { ($0.kind != nil ? 0 : 1, -$0.rssi) < ($1.kind != nil ? 0 : 1, -$1.rssi) }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        let kind = pendingKinds[id] ?? devices.first(where: { $0.id == id })?.kind ?? .heartRateSensor
        let driver: WearableDriver = kind == .cmfWatch
            ? CMFWatchDriver(peripheral: peripheral)
            : HeartRateSensorDriver(peripheral: peripheral)
        driver.onEvent = { [weak self] event in self?.handle(event, from: peripheral) }
        drivers[id]?.stop()
        drivers[id] = driver
        connected.insert(id)

        if !devices.contains(where: { $0.id == id }) {
            devices.append(KnownDevice(id: id, name: peripheral.name ?? kind.title, kind: kind))
            KnownDevice.saveAll(devices)
        }
        append(.info, peripheral.name ?? "Device", "Connected")
        driver.start()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status[peripheral.identifier] = "Couldn't connect: \(error?.localizedDescription ?? "unknown error")"
        append(.error, peripheral.name ?? "Device", status[peripheral.identifier] ?? "")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        drivers[id]?.stop()
        drivers[id] = nil
        connected.remove(id)
        syncing.remove(id)
        if liveHeartRate != nil, devices.first(where: { $0.id == id })?.kind == .heartRateSensor { liveHeartRate = nil }
        status[id] = "Disconnected"
        append(.info, peripheral.name ?? "Device", "Disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
        // iOS keeps a pending connect alive indefinitely — the watch reconnects as soon as it is back in range.
        if let known = devices.first(where: { $0.id == id }), known.autoConnect {
            pendingKinds[id] = known.kind
            central.connect(peripheral, options: nil)
        }
    }

    // MARK: Driver events

    private func handle(_ event: DriverEvent, from peripheral: CBPeripheral) {
        let id = peripheral.identifier
        let name = peripheral.name ?? "Device"
        switch event {
        case .status(let s): status[id] = s
        case .ready: update(id) { $0.autoConnect = true }
        case .battery(let level): update(id) { $0.battery = level }
        case .firmware(let fw): update(id) { $0.firmware = fw }
        case .serial(let sn): update(id) { $0.serial = sn }
        case .batch(let batch):
            if !batch.isEmpty { onBatch?(batch) }
        case .liveHeartRate(let bpm): liveHeartRate = bpm
        case .syncStarted: syncing.insert(id)
        case .syncFinished:
            syncing.remove(id)
            update(id) { $0.lastSync = Date() }
        case .log(let dir, let text): append(dir, name, text)
        case .failed(let message):
            status[id] = message
            syncing.remove(id)
        }
    }

    private func append(_ dir: LogLine.Direction, _ device: String, _ text: String) {
        log.append(LogLine(direction: dir, device: device, text: text))
        if log.count > 3000 { log.removeFirst(log.count - 3000) }
    }

    private func update(_ id: UUID, _ change: (inout KnownDevice) -> Void) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        change(&devices[i])
        KnownDevice.saveAll(devices)
    }
}
