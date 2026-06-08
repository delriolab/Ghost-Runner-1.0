import Foundation
import CoreBluetooth
import Combine

final class BLEManager: NSObject, ObservableObject {

    static let serviceUUID = CBUUID(string: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")
    static let controlUUID = CBUUID(string: "E2C56DB6-DFFB-48D2-B060-D0F5A71096E0")
    static let triggerUUID = CBUUID(string: "E2C56DB7-DFFB-48D2-B060-D0F5A71096E0")

    @Published var isConnected = false
    @Published var statusText = "Scanning…"

    let hitPublisher = PassthroughSubject<Void, Never>()

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controlChar: CBCharacteristic?
    private var triggerChar: CBCharacteristic?

    private var isReady = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

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

    private func write(_ bytes: [UInt8]) {
        guard let p = peripheral, let c = controlChar else { return }
        p.writeValue(Data(bytes), for: c, type: .withResponse)
    }
}

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            statusText = "Scanning"
            central.scanForPeripherals(withServices: [Self.serviceUUID])
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover p: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        if peripheral == nil {
            peripheral = p
            p.delegate = self
            central.connect(p)
            statusText = "Connecting"
        }
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
        statusText = "Reconnecting"
        central.connect(p)
    }
}

extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ p: CBPeripheral,
                    didDiscoverServices error: Error?) {

        p.services?.forEach {
            if $0.uuid == Self.serviceUUID {
                p.discoverCharacteristics(
                    [Self.controlUUID, Self.triggerUUID],
                    for: $0
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
                p.setNotifyValue(true, for: $0)
            }
        }

        if controlChar != nil && triggerChar != nil {
            isReady = true
        }
    }

    func peripheral(_ p: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {

        guard characteristic.uuid == Self.triggerUUID,
              let data = characteristic.value,
              data.first == 0x01 else { return }

        hitPublisher.send()
    }
}
