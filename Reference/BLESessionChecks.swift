// Executes the production PCRBluetooth coordinator with a deterministic transport double.
// No radio, no hardware assertion. UI scene/tab call sites are additionally source-tested.
import Foundation
import CoreBluetooth

@main struct BLESessionChecks {
    static func connected(_ name: String = "PCR-NFCPRO", withoutResponse: Bool = false) -> (PCRBluetooth, CBCentralManager, CBPeripheral, [CBCharacteristic]) {
        let fields = zip(PCRDeviceInformation.fields, ["TD5322A", "1.0.0", "V3.0.1", "TD5322A_V3.0.1"]).map {
            CBCharacteristic($0.0.uuid, .read, value: $0.1)
        }
        let tx = CBCharacteristic("FF02", withoutResponse ? .writeWithoutResponse : .write)
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
    static func reply(_ step: NFCProIdentify.Step, _ payload: [UInt8] = []) -> Data {
        let body: [UInt8] = [0xD5, step.command &+ 1] + payload
        return NFCProIdentify.ack + Data([0,0,255,UInt8(body.count),UInt8(truncatingIfNeeded: -body.count)] + body + [UInt8(truncatingIfNeeded: -body.reduce(0, { $0 + Int($1) })),0])
    }
    static func identifyChecks() {
        for noResponse in [false, true] {
            let (b,c,p,_) = connected(withoutResponse: noResponse)
            let tx = p.services![1].characteristics![0], rx = p.services![1].characteristics![1]
            p.writeLimit = 3 // Exercise actual fragmentation even for the short allowlisted commands.
            var acknowledged = 0
            func drainWrites() {
                while !noResponse && acknowledged < p.writes.count {
                    acknowledged += 1; b.peripheral(p, didWriteValueFor: tx, error: nil)
                }
            }
            func notify(_ data: Data) {
                // One byte at a time: ACK/header/payload/checksum may cross any BLE boundary.
                for byte in data { rx.value = Data([byte]); b.peripheral(p, didUpdateValueFor: rx, error: nil) }
            }
            for hasCard in [false, true] {
                let start = p.writes.count
                if noResponse { p.canSendWriteWithoutResponse = false }
                b.identifyCard(); b.identifyCard(); b.readVersion(); b.readDeviceInformation()
                precondition(b.identifying && b.busy)
                if noResponse {
                    precondition(p.writes.count == start)
                    p.canSendWriteWithoutResponse = true; b.peripheralIsReady(toSendWriteWithoutResponse: p)
                }
                drainWrites(); RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                drainWrites(); RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                for step in NFCProIdentify.Step.allCases {
                    // Deliver a complete response before the final write callback as well.
                    let payload: [UInt8] = step == .poll ? (hasCard ? [1,1,0,4,8,4,0xA5,0xA5,0xA5,0xA5] : [0]) : []
                    notify(reply(step,payload)); drainWrites()
                }
                precondition(!b.busy && !b.identifying && b.connected && b.ready && c.cancellations == 0)
                precondition((b.identifiedCard != nil) == hasCard)
                precondition(hasCard || b.identifyMessage.contains("未发现"))
                let expected = NFCProIdentify.wake + NFCProIdentify.ack + NFCProIdentify.Step.allCases.reduce(Data()) { $0 + $1.packet }
                precondition(p.writes.dropFirst(start).reduce(Data(), +) == expected)
                precondition(p.writes.allSatisfy { $0.count <= 3 })
            }
            b.identifyCard(); b.cancelIdentification()
            let stopped = p.writes.count
            drainWrites(); notify(reply(.poll,[0]))
            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
            precondition(!b.connected && !b.identifying && b.identifiedCard == nil && p.writes.count == stopped)
        }
        // Cancel during an active poll, late notification, explicit reconnect and clean new attempt.
        let (b,c,p,_) = connected()
        let tx = p.services![1].characteristics![0], rx = p.services![1].characteristics![1]
        func doneWrite() { b.peripheral(p, didWriteValueFor: tx, error: nil) }
        func notify(_ step: NFCProIdentify.Step, _ payload: [UInt8] = []) {
            rx.value = reply(step,payload); b.peripheral(p, didUpdateValueFor: rx, error: nil)
        }
        b.identifyCard(); doneWrite(); RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        doneWrite(); RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        doneWrite(); notify(.sam); doneWrite(); notify(.retries); doneWrite()
        b.cancelIdentification(); notify(.poll,[0]); precondition(!b.connected && !b.busy)
        b.centralManager(c, didDisconnectPeripheral: p, error: nil)
        b.requestConnection(b.devices[0]); b.confirmConnection(b.devices[0], profileID: BLEProfile.builtin.id, remember: false)
        b.centralManager(c, didConnect: p); b.peripheral(p, didDiscoverServices: nil)
        for service in p.services! { b.peripheral(p, didDiscoverCharacteristicsFor: service, error: nil) }
        b.peripheral(p, didUpdateNotificationStateFor: rx, error: nil)
        b.identifyCard(); notify(.poll,[0]) // Startup quarantine, not a new result.
        precondition(b.identifying && b.identifiedCard == nil)
        doneWrite(); RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        doneWrite(); RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        doneWrite(); notify(.sam); doneWrite(); notify(.retries); doneWrite()
        RunLoop.main.run(until: Date().addingTimeInterval(4.2))
        precondition(!b.connected && !b.busy && b.identifyMessage.contains("不能据此判定无卡"))
        let (back,_,_,_) = connected(); back.identifyCard(); back.setForeground(false)
        precondition(!back.identifying && !back.busy && back.lastDisconnectReason == .background)
        let (unknown,_,pu,_) = connected("PCR-NFCPRO clone"); unknown.identifyCard()
        precondition(pu.writes.isEmpty && !unknown.identifying)
        print("PASS: actual NFCPRO coordinator, synthetic transport only: 3-byte MTU, both write modes, early response, busy guard, finite no-card, success, repeated click, startup/poll cancel, late notification quarantine, reconnect, timeout and background.")
    }
    static func main() {
        identifyChecks()
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
