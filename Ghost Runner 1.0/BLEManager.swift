import Foundation
import CoreBluetooth
import Combine

final class BLEManager: NSObject, ObservableObject {

    @Published var statusText = "Initializing..."

    private var central: CBCentralManager!

    override init() {
        super.init()

        print("BLEManager INIT")

        central = CBCentralManager(delegate: self, queue: nil)
    }
}

extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {

        print("STATE:", central.state.rawValue)

        if central.state == .poweredOn {

            print("BLE ON → SCANNING")

            statusText = "Scanning"

            central.scanForPeripherals(withServices: nil)

        } else {
            print("Bluetooth not ready:", central.state.rawValue)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        let name = peripheral.name ?? "nil"
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "nil"

        print("FOUND DEVICE → name:", name, "| adv:", advName)
    }
}
