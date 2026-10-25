// Real coordinator differential regression; synthetic transport only, no private payloads.
import Foundation
import CoreBluetooth
@main struct BLEFastRegression {
    static func main() {
        let suite = "LinkCard-fast-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let mode = CommandLine.arguments.last!
        var preferences = BLEPreferences()
        let tx = CBCharacteristic("0000FF02-0000-1000-8000-00805F9B34FB", [.write,.notify])
        let rx = CBCharacteristic("0000FF01-0000-1000-8000-00805F9B34FB", [.notify,.read])
        let service = CBService("0000FF00-0000-1000-8000-00805F9B34FB", [tx,rx])
        let peripheral = CBPeripheral(name: "PCR-NFCPRO(BLE)", services: [service])
        if mode == "trusted" { preferences.trusted = [BLETrust(id: peripheral.identifier, profileID: BLEProfile.builtin.id)] }
        precondition(preferences.save(to: defaults))
        let ble = PCRBluetooth(preferencesStore: BLEPreferencesStore(defaults: defaults))
        ble.setForeground(true)
        let central = CBCentralManager.latest!
        ble.centralManagerDidUpdateState(central)
        ble.centralManager(central, didDiscover: peripheral, advertisementData: [CBAdvertisementDataLocalNameKey: peripheral.name!], rssi: -40)
        let passed: Bool
        if mode == "trusted" {
            passed = ble.active && !ble.scanning && central.connections == 1
        } else if mode == "prompt" {
            passed = ble.connectionPrompt != nil && ble.scanning && central.connections == 0
        } else {
            ble.confirmConnection(ble.devices[0], profileID: BLEProfile.builtin.id, remember: false)
            ble.centralManager(central, didConnect: peripheral)
            ble.peripheral(peripheral, didDiscoverServices: nil)
            ble.peripheral(peripheral, didDiscoverCharacteristicsFor: service, error: nil)
            ble.peripheral(peripheral, didUpdateNotificationStateFor: rx, error: nil)
            // The old build reaches ready, then rejects the actual long-form FF00 channel.
            precondition(ble.ready && peripheral.subscriptions == 1)
            passed = ble.canIdentify
        }
        precondition(peripheral.reads.isEmpty && peripheral.writes.isEmpty)
        ble.setForeground(false)
        exit(passed ? 0 : 1)
    }
}
