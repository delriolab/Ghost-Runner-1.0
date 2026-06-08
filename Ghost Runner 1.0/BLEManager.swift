import Foundation
import CoreBluetooth
import Combine

final class BLEManager: NSObject, ObservableObject {

    @Published var statusText = "Starting..."

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
            print("SCANNING STARTED")
            statusText = "Scanning"
            central.scanForPeripherals(withServices: nil)
        } else {
            print("Bluetooth not ready")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        let name = peripheral.name ?? "nil"
        let adv = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "nil"

        print("FOUND:", name, "| adv:", adv)
    }
}
