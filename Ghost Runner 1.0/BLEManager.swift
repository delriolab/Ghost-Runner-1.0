import Foundation
import CoreBluetooth
import Combine

final class BLEManager: NSObject, ObservableObject {

    // MARK: - UUIDs
    static let serviceUUID = CBUUID(string: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")
    static let controlUUID = CBUUID(string: "E2C56DB6-DFFB-48D2-B060-D0F5A71096E0")
    static let triggerUUID = CBUUID(string: "E2C56DB7-DFFB-48D2-B060-D0F5A71096E0")

    // MARK: - UI State
    @Published var isConnected = false
    @Published var statusText = "Scanning..."

    let hitPublisher = PassthroughSubject<Void, Never>()

    // MARK: - BLE
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
        guard isReady else {
            print("Not ready to send START")
            return
        }
        write([0x01])
    }

    func sendStop() {
        guard isReady else {
            print("Not ready to send STOP")
            return
        }
        write([0x00])
    }

    func sendDelay(_ seconds: Double) {
        let val = UInt16(seconds * 10)
        write([UInt8(val & 0xFF), UInt8(val >> 8)])
    }

    private func write(_ bytes: [UInt8]) {
        guard let p = peripheral, let c = controlChar else {
            print("Write failed: missing peripheral or characteristic")
            return
        }

        print("Sending:", bytes)
        p.writeValue(Data(bytes), for: c, type: .withResponse)
    }
}

// MARK: - Central Delegate

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            statusText = "Scanning"
            print("BLE ON → Scanning")

            // ✅ Scan everything
            central.scanForPeripherals(withServices: nil)
        } else {
            statusText = "Bluetooth not available"
            print("Bluetooth state:", central.state.rawValue)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover p: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        let name = p.name ?? "nil"
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "nil"

        print("Found device | name:", name, "| adv:", advName)

        // ✅ Robust matching (critical fix)
        if name.contains("GhostRunner") || advName.contains("GhostRunner") {

            // prevent re-connecting loop
            if peripheral != nil { return }

            print("Matched GhostRunner → connecting")

            peripheral = p
            p.delegate = self

            central.stopScan()
            statusText = "Connecting"

            central.connect(p)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect p: CBPeripheral) {

        print("Connected to GhostRunner")

        isConnected = true
        statusText = "Connected"

        p.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect p: CBPeripheral,
                        error: Error?) {

        print("Failed to connect:", error?.localizedDescription ?? "unknown")

        peripheral = nil
        isConnected = false
        statusText = "Retrying"

        central.scanForPeripherals(withServices: nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral p: CBPeripheral,
                        error: Error?) {

        print("Disconnected")

        peripheral = nil
        isReady = false
        controlChar = nil
        triggerChar = nil

        isConnected = false
        statusText = "Reconnecting"

        central.scanForPeripherals(withServices: nil)
    }
}

// MARK: - Peripheral Delegate

extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ p: CBPeripheral,
                    didDiscoverServices error: Error?) {

        print("Services discovered")

        p.services?.forEach { service in
            if service.uuid == Self.serviceUUID {
                print("Found GhostRunner service")

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

        print("Characteristics discovered")

        service.characteristics?.forEach {

            if $0.uuid == Self.controlUUID {
                controlChar = $0
                print("Control characteristic ready")
            }

            if $0.uuid == Self.triggerUUID {
                triggerChar = $0
                print("Trigger characteristic ready")

                p.setNotifyValue(true, for: $0)
            }
        }

        if controlChar != nil && triggerChar != nil {
            isReady = true
            print("BLE FULLY READY")
        }
    }

    func peripheral(_ p: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {

        guard characteristic.uuid == Self.triggerUUID,
              let data = characteristic.value,
              data.first == 0x01 else { return }

        print("HIT received")

        hitPublisher.send()
    }
}
