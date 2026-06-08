import Foundation
import CoreBluetooth
import Combine

final class BLEManager: NSObject, ObservableObject {

    // MARK: - UUIDs (must match firmware)
    static let serviceUUID = CBUUID(string: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")
    static let controlUUID = CBUUID(string: "E2C56DB6-DFFB-48D2-B060-D0F5A71096E0")
    static let triggerUUID = CBUUID(string: "E2C56DB7-DFFB-48D2-B060-D0F5A71096E0")

    // MARK: - Published State
    @Published var isConnected = false
    @Published var statusText = "Scanning..."

    let hitPublisher = PassthroughSubject<Void, Never>()

    // MARK: - BLE Internals
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    private var controlChar: CBCharacteristic?
    private var triggerChar: CBCharacteristic?

    private var isReady = false

    // MARK: - Init
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    func sendStart() {
        guard isReady else { return }
        write([0x01])
    }

    func sendStop() {
        guard isReady else { return }
        write([0x00])
    }

    func sendDelay(_ seconds: Double) {
        let val = UInt16(seconds * 10)
        write([UInt8(val & 0xFF), UInt8(val >> 8)])
    }

    // MARK: - Private Write

    private func write(_ bytes: [UInt8]) {
        guard let p = peripheral, let c = controlChar else { return }
        p.writeValue(Data(bytes), for: c, type: .withResponse)
    }
}

// MARK: - Central Manager Delegate

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            statusText = "Scanning"
           
            // ✅ FIX: scan for ALL devices (not filtered)
            central.scanForPeripherals(withServices: nil)
        } else {
            statusText = "Bluetooth not available"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover p: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        // ✅ DEBUG: see all devices found
        print("Found:", p.name ?? "Unknown")

        // ✅ Only connect to GhostRunner
        guard p.name == "GhostRunner" else { return }

        // Prevent multiple connections
        guard peripheral == nil else { return }

        peripheral = p
        p.delegate = self

        central.stopScan()

        statusText = "Connecting"
        central.connect(p)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect p: CBPeripheral) {

        isConnected = true
        statusText = "Connected"

        p.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral p: CBPeripheral,
                        error: Error?) {

        isConnected = false
        isReady = false
        controlChar = nil
        triggerChar = nil

        statusText = "Reconnecting"

        central.connect(p)
    }
}

// MARK: - Peripheral Delegate

extension BLEManager: CBPeripheralDelegate {
    
    func peripheral(_ p: CBPeripheral,
                    didDiscoverServices error: Error?) {
        
        p.services?.forEach { service in
            if service.uuid == Self.serviceUUID {
                p.discoverCharacteristics(
                    [Self.controlUUID, Self.triggerUUID],
                    for: service
                )
            }
        }
    }
    
    func peripheral(_ p: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        
        service.characteristics?.forEach {
            
            if $0.uuid == Self.controlUUID {
                controlChar = $0
            }
            
            if $0.uuid == Self.triggerUUID {
                triggerChar = $0
                
                // Enable notifications
                p.setNotifyValue(true, for: $0)
            }
        }
        
        // ✅ Ready once both are found
        if controlChar != nil && triggerChar != nil {
            isReady = true
            print("BLE Ready")
        }
    }
    
    func peripheral(_ p: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        
        guard characteristic.uuid == Self.triggerUUID,
              let data = characteristic.value,
              data.first == 0x01 else { return }
        
        // HIT received
        hitPublisher.send()
    }
}
