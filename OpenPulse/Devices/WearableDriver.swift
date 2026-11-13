import Foundation
import CoreBluetooth

/// Events a device driver reports back to the Bluetooth manager.
enum DriverEvent {
    case status(String)
    case ready
    case battery(Int)
    case firmware(String)
    case serial(String)
    case batch(HealthBatch)
    case liveHeartRate(Int)
    case syncStarted
    case syncFinished
    case log(LogLine.Direction, String)
    case failed(String)
}

/// Base class for a "driver" — the code that speaks one family of devices' protocol.
/// Adding support for a new brand means adding one subclass.
/// (Each subclass declares `CBPeripheralDelegate` itself so its callbacks are exposed to CoreBluetooth.)
class WearableDriver: NSObject {
    let peripheral: CBPeripheral
    var onEvent: ((DriverEvent) -> Void)?

    var kind: DeviceKind { fatalError("Subclasses must override kind") }
    var deviceName: String { peripheral.name ?? kind.title }

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
    }

    /// Called once the BLE link is up.
    func start() {}
    /// Pull recorded data from the device.
    func sync() {}
    /// Called on disconnect; flush anything buffered.
    func stop() {}
    /// Optional device-specific action (vibrate to find the watch).
    func find() {}
    func apply(_ settings: WatchSettings) {}

    func emit(_ e: DriverEvent) { onEvent?(e) }
    func log(_ d: LogLine.Direction, _ text: String) { onEvent?(.log(d, text)) }
}
