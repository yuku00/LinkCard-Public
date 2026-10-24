// Executes the production PCRBluetooth coordinator with a deterministic transport double.
// No radio, no hardware assertion. UI scene/tab call sites are additionally source-tested.
import Foundation
import CoreBluetooth

@main struct BLESessionChecks {
    static func connected(_ name: String = "PCR-NFCPRO") -> (PCRBluetooth, CBCentralManager, CBPeripheral, [CBCharacteristic]) {
        let fields = zip(PCRDeviceInformation.fields, ["TD5322A", "1.0.0", "V3.0.1", "TD5322A_V3.0.1"]).map {
            CBCharacteristic($0.0.uuid, .read, value: $0.1)
        }
        let tx = CBCharacteristic("FF02", .write)
        let rx = CBCharacteristic("FF01", .notify)
        let p = CBPeripheral(name: name, services: [CBService("180A", fields), CBService("FF00", [tx, rx])])
        let b = PCRBluetooth()
        b.setAutomaticScanning(false); b.setForeground(true); b.scan()
        let c = CBCentralManager.latest!
        b.centralManagerDidUpdateState(c)
        b.centralManager(c, didDiscover: p, advertisementData: [CBAdvertisementDataLocalNameKey: name], rssi: -45)
        precondition(b.devices.count == 1)
        b.requestConnection(b.devices[0])
        b.confirmConnection(b.devices[0], profileID: BLEProfile.builtin.id, remember: false)
        b.connectionPromptDidDisappear()
        b.centralManager(c, didConnect: p)
        b.peripheral(p, didDiscoverServices: nil)
        for service in p.services! { b.peripheral(p, didDiscoverCharacteristicsFor: service, error: nil) }
        b.peripheral(p, didUpdateNotificationStateFor: rx, error: nil)
        precondition(b.connected && b.ready && b.canReadDeviceInformation && c.cancellations == 0)
        return (b, c, p, fields)
    }
    static func main() {
        let (b, c, p, fields) = connected()
        precondition(!b.canQuery, "NFCPRO must never send text commands")
        for _ in 0..<2 {
            b.readDeviceInformation()
            precondition(b.busy)
            for field in fields { b.peripheral(p, didUpdateValueFor: field, error: nil) }
            precondition(b.connected && b.active && b.ready && !b.busy && !b.readingDeviceInformation)
            precondition(b.canReadDeviceInformation && c.cancellations == 0 && p.subscriptions == 1)
            precondition(b.deviceInformation["2A28"] == "V3.0.1")
        }
        precondition(p.reads.count == 8 && p.writes.isEmpty)
        b.enterDeviceFlow() // Return to the tab; no connection lifecycle owned by the page.
        precondition(b.connected && c.cancellations == 0)
        b.setForeground(false)
        precondition(!b.connected && !b.busy && c.cancellations == 1 && b.lastDisconnectReason == .background)
        b.centralManager(c, didDisconnectPeripheral: p, error: nil)
        precondition(!b.active)

        let (manual, cm, pm, _) = connected()
        manual.setAutomaticScanning(true)
        let scans = cm.scans
        manual.disconnect()
        manual.centralManager(cm, didDisconnectPeripheral: pm, error: nil)
        manual.setForeground(false); manual.setForeground(true); manual.enterDeviceFlow()
        precondition(!manual.active && !manual.scanning && cm.scans == scans && cm.connections == 1)
        precondition(manual.lastDisconnectReason == .user)

        let (remote, cr, pr, _) = connected()
        remote.centralManager(cr, didDisconnectPeripheral: pr, error: nil)
        precondition(!remote.active && !remote.connected && remote.lastDisconnectReason == .remote)
        let (off, co, _, _) = connected()
        co.state = .poweredOff; off.centralManagerDidUpdateState(co)
        precondition(!off.active && !off.connected && off.lastDisconnectReason == .bluetooth)

        let (text, ct, pt, _) = connected("PcrGP_V2.0(BLE)")
        precondition(text.canQuery)
        let tx = pt.services![1].characteristics![0]
        let rx = pt.services![1].characteristics![1]
        for version in ["2.3.4", "2.3.5"] {
            text.readVersion()
            text.peripheral(pt, didWriteValueFor: tx, error: nil)
            rx.value = Data("101:OK WITH TEXT\r\nFirmware: \(version)\r\n".utf8)
            text.peripheral(pt, didUpdateValueFor: rx, error: nil)
            precondition(text.result.contains(version) && !text.busy && text.connected && text.canQuery)
        }
        precondition(ct.cancellations == 0 && pt.writes.count == 2 && pt.subscriptions == 1)
        // A real request deadline still ends an unresponsive transaction.
        text.readVersion()
        RunLoop.main.run(until: Date().addingTimeInterval(4.2))
        precondition(!text.connected && !text.busy && ct.cancellations == 1 && text.lastDisconnectReason == .timeout)
        print("PASS: actual PCRBluetooth coordinator; two standard reads, two text queries, retained subscriptions, tab re-entry, background close, manual suppression and real query timeout. Mock transport, not hardware.")
    }
}
