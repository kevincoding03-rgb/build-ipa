//  Look4Sat iOS port — Bluetooth radio remote control (C-class framework)
//  Re-implements the Android Bluetooth CAT (Command to transceiver) layer
//  with CoreBluetooth.  License: GPL-3.0
//
//  STATUS: C-class. Framework compiles against CoreBluetooth and exposes
//  a clean async API, but the physical radio protocol paths (FT-817 /
//  FT-857 / IC-705 CAT over SPP) have NOT been verified against real
//  hardware on iOS — that requires a Mac + a paired SPP radio and is out
//  of scope for this build. Treat this as a working skeleton:
//    - Device discovery + connect/disconnect: real CoreBluetooth.
//    - CAT command framing: mirrors the Kotlin Ft817CatProtocol /
//      Ic705Controller byte formats (unverified end-to-end).
//    - SSTV / audio path: not ported (Android AudioRecord/AudioTrack has
//      no 1:1 CoreAudio equivalent exposed; requires AVAudioEngine).
import CoreBluetooth
import Foundation
import Look4SatCore

/// A transceiver radio model known to the app.
enum RadioModel {
    case ft817, ft857, ic705

    /// Frequency-set command. 10 Hz BCD (FT) vs 1 Hz BCD CI-V (IC-705).
    func setFreqCommand(_ hz: Int64) -> [UInt8]? {
        switch self {
        case .ft817, .ft857: return Ft817CatProtocol.buildSetFreqCommand(hz)
        case .ic705:         return IcomCivProtocol.buildSetFreqCommand(hz)
        }
    }

    /// Mode-set command.
    func setModeCommand(_ mode: String) -> [UInt8]? {
        switch self {
        case .ft817, .ft857: return Ft817CatProtocol.buildSetModeCommand(mode)
        case .ic705:         return IcomCivProtocol.buildSetModeCommand(mode)
        }
    }
}

/// One CAT command (mode / freq / band).
struct CatCommand {
    let body: [UInt8]
}

/// The BLE radio link. Discovery, connection, and CAT command send.
final class RadioLink: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var isConnected = false
    @Published var lastError: String?
    @Published var model: RadioModel = .ft817

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var service: CBService?
    private var catChar: CBCharacteristic?
    private var readChar: CBCharacteristic?
    private let queue = DispatchQueue(label: "com.look4sat.radio")

    private var onRead: (([UInt8]) -> Void)?
    private var onWrite: (([UInt8]) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: discovery

    func scan() {
        central.scanForPeripherals(withServices: nil)
    }

    func connect(_ p: CBPeripheral) {
        stopScan()
        if let current = peripheral { central.cancelPeripheralConnection(current) }
        peripheral = p
        central.connect(p)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        isConnected = false
    }

    private func stopScan() { central.stopScan() }

    /// Set the radio frequency on the selected model.
    @discardableResult
    func setFrequency(_ hz: Int64) -> Bool {
        guard let bytes = model.setFreqCommand(hz) else { return false }
        return write(bytes)
    }

    /// Set the operating mode on the selected model.
    @discardableResult
    func setMode(_ mode: String) -> Bool {
        guard let bytes = model.setModeCommand(mode) else { return false }
        return write(bytes)
    }

    /// Write raw bytes to the CAT characteristic.
    @discardableResult
    private func write(_ bytes: [UInt8]) -> Bool {
        guard let c = catChar else { lastError = "CAT characteristic not found"; return false }
        guard let p = peripheral else { return false }
        p.write(Data(bytes), for: c, type: .withResponse)
        return true
    }

    func subscribeRead(_ handler: @escaping ([UInt8]) -> Void) { onRead = handler }
    func subscribeWrite(_ handler: @escaping ([UInt8]) -> Void) { onWrite = handler }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        if manager.state == .poweredOn { scan() }
    }

    func centralManager(_ central: CBCentralManager,
                       didDiscover p: CBPeripheral,
                       advertisementData: [String: Any], rssi: NSNumber) {
        // Filter by name later via a user-picked list.
    }

    func centralManager(_ central: CBCentralManager,
                       didConnect p: CBPeripheral) {
        p.delegate = self
        p.discoverServices(nil)
        isConnected = true
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral,
                       error: Error?) {
        isConnected = false
        if let e = error { lastError = e.localizedDescription }
    }

    // MARK: CBPeripheralDelegate (forwarded)
}

extension RadioLink: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            p.discoverCharacteristics(nil, for: s)
            if s.uuid.isEqual(CBUUID(string: "0000FF00-0000-1000-8000-00805F9B34FB")) {
                service = s
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService,
                    error: Error?) {
        for c in s.characteristics ?? [] {
            let props = c.properties
            if props.contains(.write) || props.contains(.writeWithoutResponse) {
                catChar = c
            }
            if props.contains(.read) || props.contains(.notify) {
                readChar = c
                p.setNotifyValue(true, for: c)
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic,
                    error: Error?) {
        if let d = c.value { onRead?(Array(d)) }
    }
}
