import Foundation
import CoreBluetooth

/// Standard Bluetooth Heart Rate Profile — works with any chest strap, armband or
/// watch that broadcasts heart rate (Polar, Garmin, Wahoo, Coros, Suunto, Amazfit…).
/// Beat-to-beat (RR) intervals are turned into real HRV (RMSSD) once per minute.
final class HeartRateSensorDriver: WearableDriver, CBPeripheralDelegate {
    static let hrService = CBUUID(string: "180D")
    static let hrMeasurement = CBUUID(string: "2A37")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    override var kind: DeviceKind { .heartRateSensor }

    private var sourceName: String { peripheral.name ?? "HR Sensor" }
    private var buffer = HealthBatch()
    private var rr = RRWindowAccumulator(windowSeconds: 60)
    private var lastStoredHR: Date = .distantPast
    private var flushTimer: Timer?

    override func start() {
        peripheral.delegate = self
        buffer = HealthBatch(source: sourceName)
        emit(.status("Discovering…"))
        peripheral.discoverServices([Self.hrService, Self.batteryService])
    }

    override func stop() {
        flushTimer?.invalidate()
        flushTimer = nil
        flush()
    }

    override func sync() { flush() }

    private func flush() {
        guard !buffer.isEmpty else { return }
        emit(.batch(buffer))
        log(.info, "Stored \(buffer.summary)")
        buffer = HealthBatch(source: sourceName)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { emit(.failed(error.localizedDescription)); return }
        for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == Self.hrMeasurement {
                peripheral.setNotifyValue(true, for: c)
                emit(.status("Streaming"))
                emit(.ready)
                flushTimer?.invalidate()
                flushTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.flush() }
            } else if c.uuid == Self.batteryLevel {
                peripheral.readValue(for: c)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        let bytes = [UInt8](value)
        let now = Date()

        if characteristic.uuid == Self.batteryLevel, let level = bytes.first {
            emit(.battery(Int(level)))
            return
        }
        guard characteristic.uuid == Self.hrMeasurement, let m = HeartRateMeasurement(bytes) else { return }
        if m.sensorContact == false { return }

        emit(.liveHeartRate(m.bpm))
        // Store one heart-rate sample every 5 seconds — plenty for strain, small on disk.
        if now.timeIntervalSince(lastStoredHR) >= 5, m.bpm > 0 {
            buffer.heartRate.append(HRPoint(date: now, bpm: m.bpm))
            lastStoredHR = now
        }
        if !m.rrIntervals.isEmpty, let point = rr.add(m.rrIntervals, at: now) {
            buffer.hrv.append(point)
        }
    }
}
