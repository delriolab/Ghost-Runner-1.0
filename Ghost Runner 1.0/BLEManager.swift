import Foundation
import CoreBluetooth
import Combine

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @Published var connectionStatus: String = "Disconnected"
    
    // This feeds your ContentView's .onReceive listener instantly
    let triggerPublisher = PassthroughSubject<Void, Never>()
    
    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic? // For receiving data from sensor
    private var rxCharacteristic: CBCharacteristic? // For writing data to sensor
    
    // Nordic UART Service Identifiers used by Adafruit's UARTService
    private let uartServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let txCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    
    private var incomingBuffer = ""

    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - App to Sensor Commands
    
    func startMonitoring() {
        sendStringCommand("START")
        connectionStatus = "Connected: Monitoring"
    }
    
    func stopMonitoring() {
        sendStringCommand("STOP")
        connectionStatus = "Connected: Idle"
    }
    
    func sendDelay(_ seconds: Double) {
        // Formats to "T=4.1" to match Andy's script command parsing
        sendStringCommand(String(format: "T=%.2f", seconds))
    }
    
    private func sendStringCommand(_ command: String) {
        guard let peripheral = discoveredPeripheral, let rxChar = rxCharacteristic else { return }
        let completeCommand = "\(command)\n"
        if let data = completeCommand.data(using: .utf8) {
            peripheral.writeValue(data, for: rxChar, type: .withoutResponse)
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            connectionStatus = "Searching for GhostRunner..."
            centralManager.scanForPeripherals(withServices: [uartServiceUUID], options: nil)
        } else {
            connectionStatus = "Bluetooth Disabled"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        if name.contains("GhostRunner") {
            centralManager.stopScan()
            discoveredPeripheral = peripheral
            discoveredPeripheral?.delegate = self
            connectionStatus = "Connecting..."
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionStatus = "Connected: Idle"
        peripheral.discoverServices([uartServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        discoveredPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        connectionStatus = "Disconnected. Reconnecting..."
        centralManager.scanForPeripherals(withServices: [uartServiceUUID], options: nil)
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == uartServiceUUID {
            peripheral.discoverCharacteristics([txCharacteristicUUID, rxCharacteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == txCharacteristicUUID {
                peripheral.setNotifyValue(true, for: characteristic)
                txCharacteristic = characteristic
            } else if characteristic.uuid == rxCharacteristicUUID {
                rxCharacteristic = characteristic
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == txCharacteristicUUID, let data = characteristic.value else { return }
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        
        incomingBuffer += chunk
        
        // Process complete text lines separated by newlines
        while incomingBuffer.contains("\n") {
            let parts = incomingBuffer.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let line = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            incomingBuffer = parts.count > 1 ? String(parts[1]) : ""
            
            // Listen exactly for Andy's "HIT" log token
            if line.hasPrefix("HIT") {
                DispatchQueue.main.async {
                    self.triggerPublisher.send()
                }
            }
        }
    }
}
