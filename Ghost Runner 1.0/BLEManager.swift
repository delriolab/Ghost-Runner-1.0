//
//  BLEManager.swift
//  Ghost Runner 1.0
//
//  Created by Alexander del Rio on 4/3/26.
//

import Foundation
import CoreBluetooth
import Combine
class BLEManager: NSObject, ObservableObject {
@Published var connectionStatus = "Disconnected"
let triggerPublisher = PassthroughSubject<Void, Never>()

private var centralManager: CBCentralManager
private var peripheral: CBPeripheral?

private var controlCharacteristic: CBCharacteristic?
private var triggerCharacteristic: CBCharacteristic?

private let ghostServiceUUID = CBUUID(string: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")
private let controlCharUUID = CBUUID(string: "E2C56DB6-DFFB-48D2-B060-D0F5A71096E0")
private let triggerCharUUID = CBUUID(string: "E2C56DB7-DFFB-48D2-B060-D0F5A71096E0")

override init() {
    centralManager = CBCentralManager(delegate: nil, queue: nil)
    super.init()
    centralManager.delegate = self
}

func startMonitoring() {
    sendCommand(0x01)
}

func stopMonitoring() {
    sendCommand(0x00)
}

func sendDelay(_ seconds: Double) {
    let scaled = UInt16(seconds * 10)
    let data = Data([
        UInt8(scaled & 0xFF),
        UInt8(scaled >> 8)
    ])
    writeValue(data)
}

private func sendCommand(_ value: UInt8) {
    writeValue(Data([value]))
}

private func writeValue(_ data: Data) {
    guard let peripheral = peripheral,
          let characteristic = controlCharacteristic else { return }

    peripheral.writeValue(data, for: characteristic, type: .withResponse)
}

}
extension BLEManager: CBCentralManagerDelegate, CBPeripheralDelegate {
func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state == .poweredOn {
        connectionStatus = "Scanning"
        central.scanForPeripherals(withServices: [ghostServiceUUID])
    }
}

func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
) {
    self.peripheral = peripheral
    self.peripheral?.delegate = self
    central.stopScan()
    central.connect(peripheral)
    connectionStatus = "Connecting"
}

func centralManager(
    _ central: CBCentralManager,
    didConnect peripheral: CBPeripheral
) {
    connectionStatus = "Connected"
    peripheral.discoverServices([ghostServiceUUID])
}

func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverServices error: Error?
) {
    guard let services = peripheral.services else { return }

    for service in services where service.uuid == ghostServiceUUID {
        peripheral.discoverCharacteristics(
            [controlCharUUID, triggerCharUUID],
            for: service
        )
    }
}

func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
) {
    guard let characteristics = service.characteristics else { return }

    for characteristic in characteristics {
        if characteristic.uuid == controlCharUUID {
            controlCharacteristic = characteristic
        }

        if characteristic.uuid == triggerCharUUID {
            triggerCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
}

func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
) {
    if characteristic.uuid == triggerCharUUID {
        triggerPublisher.send(())
    }
}

} 
