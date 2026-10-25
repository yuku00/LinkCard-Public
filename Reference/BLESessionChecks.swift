// Executes the production PCRBluetooth coordinator with a deterministic transport double.
// No radio, no hardware assertion. UI scene/tab call sites are additionally source-tested.
import Foundation
import CoreBluetooth

/// Real UserDefaults read/load path with a deterministic write-rejection seam.
/// This is a persistence fault injection, not a claim of physical disk failure.
private final class RejectingPreferencesDefaults: UserDefaults, @unchecked Sendable {
    var rejectsWrites = false
    override func set(_ value: Any?, forKey defaultName: String) {
        if !rejectsWrites { super.set(value, forKey: defaultName) }
    }
}

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
        precondition(pu.writes.isEmpty && !unknown.identifying && unknown.identifyPhase == "blocked")
        precondition(unknown.status == unknown.identifyMessage && !unknown.identifyMessage.isEmpty)
        let (locked,_,pl,fields) = connected()
        locked.readDeviceInformation(); locked.identifyCard()
        precondition(locked.busy && !locked.identifying && pl.writes.isEmpty)
        precondition(locked.identifyMessage.contains("正忙") && locked.status == locked.identifyMessage)
        for field in fields { locked.peripheral(pl, didUpdateValueFor: field, error: nil) }
        locked.identifyCard()
        precondition(locked.identifying && locked.identifyPhase == "starting" && locked.status == locked.identifyMessage)
        let write = pl.services![1].characteristics![0]
        locked.peripheral(pl, didWriteValueFor: write, error: NSError(domain: "synthetic", code: 1))
        precondition(!locked.busy && locked.identifyPhase == "failed" && locked.identifyFailurePhase == "starting")
        precondition(locked.identifyMessage.contains("写入失败"))
        print("PASS: actual NFCPRO coordinator, synthetic transport only: 3-byte MTU, both write modes, early response, busy guard, finite no-card, success, repeated click, startup/poll cancel, late notification quarantine, reconnect, timeout and background.")
    }
    static func persistenceFailureChecks() {
        let suite = "LinkCard-write-failure-" + UUID().uuidString
        let store = RejectingPreferencesDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        precondition(BLEPreferences().save(to: store))
        let b = PCRBluetooth(preferencesStore: BLEPreferencesStore(defaults: store))
        b.setForeground(true)
        let c = CBCentralManager.latest!
        b.centralManagerDidUpdateState(c)
        let p = CBPeripheral(name: "PCR-NFCPRO", services: [])
        b.centralManager(c, didDiscover: p, advertisementData: [CBAdvertisementDataLocalNameKey: "PCR-NFCPRO"], rssi: -50)
        b.finishDiscovery()
        let device = b.devices[0]
        b.connectionPromptDidAppear()
        store.rejectsWrites = true
        b.confirmConnection(device, profileID: BLEProfile.builtin.id, remember: true)
        precondition(!b.active && c.connections == 0 && b.connectionPrompt?.id == p.identifier)
        precondition(b.preferences.trusted.isEmpty && BLEPreferences.load(from: store).trusted.isEmpty)
        precondition(b.status.contains("未能保存") && b.preferencesRestoreMessage != nil)
        precondition(p.reads.isEmpty && p.writes.isEmpty)
        let scans = c.scans
        b.setForeground(false); b.connectionPromptDidDisappear(); b.setForeground(true)
        c.state = .poweredOff; b.centralManagerDidUpdateState(c)
        c.state = .poweredOn; b.centralManagerDidUpdateState(c)
        precondition(!b.scanning && c.scans == scans && c.connections == 0)
        // Explicit retry after storage becomes writable commits consent once.
        store.rejectsWrites = false
        b.confirmConnection(device, profileID: BLEProfile.builtin.id, remember: true)
        precondition(b.active && c.connections == 1 && b.preferencesRestoreMessage == nil)
        precondition(BLEPreferences.load(from: store).trusted.first?.id == p.identifier)
        precondition(p.reads.isEmpty && p.writes.isEmpty)
        b.setForeground(false); b.centralManager(c, didDisconnectPeripheral: p, error: nil)
        let saved = BLEPreferences.load(from: store)
        let edits = PCRBluetooth(preferencesStore: BLEPreferencesStore(defaults: store))
        store.rejectsWrites = true
        edits.forget(p.identifier)
        precondition(edits.preferences.trusted == saved.trusted)
        edits.setAutomaticScanning(false)
        precondition(edits.preferences.autoScan && BLEPreferences.load(from: store).autoScan)
        edits.setDiscoveryPrompt(false)
        precondition(edits.preferences.showDiscoveryPrompt)
        var profile = BLEProfile.builtin
        profile.id = UUID(); profile.name = "Local fault-injection profile"
        profile.adapterID = "connect-only"
        precondition(edits.addProfile(profile) != nil && edits.preferences.profiles == saved.profiles)
        edits.setForeground(true)
        precondition(!edits.scanning && !edits.active)
        precondition(BLEPreferences.load(from: store).trusted == saved.trusted)
        edits.setForeground(false)
        store.rejectsWrites = false
        edits.forget(p.identifier)
        precondition(edits.preferences.trusted.isEmpty && BLEPreferences.load(from: store).trusted.isEmpty)
        print("PASS: real defaults round-trip with rejected writes; no unsaved trust/connect, visible failure, foreground/power suppression, failed edit rollback and explicit retry. No hardware storage failure claimed.")
    }
    static func recoveryChecks() {
        let id = UUID()
        var saved = BLEPreferences()
        saved.trusted = [BLETrust(id: id, profileID: BLEProfile.builtin.id)]
        precondition(saved.save())
        let restored = BLEPreferences.load()
        precondition(restored.trusted == saved.trusted && restored.autoScan)
        let b = PCRBluetooth(); b.setForeground(true)
        let c = CBCentralManager.latest!
        b.centralManagerDidUpdateState(c)
        let p = CBPeripheral(name: "renamed", services: [], identifier: id)
        func discover(_ peripheral: CBPeripheral) {
            b.centralManager(c, didDiscover: peripheral, advertisementData: [CBAdvertisementDataLocalNameKey: peripheral.name ?? ""], rssi: -50)
        }
        discover(p); b.finishDiscovery()
        precondition(b.active && b.connectionPrompt == nil && c.connections == 1)
        precondition(p.writes.isEmpty && p.reads.isEmpty, "Auto-connect never reads card or device information")
        b.disconnect(); b.centralManager(c, didDisconnectPeripheral: p, error: nil)
        let scans = c.scans
        b.enterDeviceFlow(); b.centralManagerDidUpdateState(c)
        precondition(!b.scanning && c.scans == scans, "Tab re-entry and duplicate poweredOn do not defeat manual cancel")
        c.state = .poweredOff; b.centralManagerDidUpdateState(c)
        c.state = .poweredOn; b.centralManagerDidUpdateState(c)
        precondition(b.scanning && c.scans == scans + 1)
        discover(p); b.finishDiscovery()
        precondition(b.active && b.connectionPrompt == nil)
        b.disconnect(); b.centralManager(c, didDisconnectPeripheral: p, error: nil)
        b.setForeground(false); b.setForeground(true)
        precondition(b.scanning, "New foreground restores saved auto permission")
        discover(p); b.finishDiscovery()
        // Background-close callback arrives after the next foreground event.
        b.setForeground(false); b.setForeground(true)
        precondition(!b.scanning)
        b.centralManager(c, didDisconnectPeripheral: p, error: nil)
        precondition(b.scanning)
        discover(p)
        b.setAutomaticScanning(false)
        b.requestConnection(b.devices[0])
        precondition(b.active && b.connectionPrompt == nil, "Manual saved selection does not ask twice")
        b.disconnect(); b.centralManager(c, didDisconnectPeripheral: p, error: nil)
        b.scan(); discover(p); b.finishDiscovery()
        precondition(b.connectionPrompt == nil && !b.active, "Auto-off cannot produce a prompt for saved UUID")
        b.confirmConnection(b.devices[0], profileID: BLEProfile.builtin.id, remember: false)
        precondition(!BLEPreferences.load().trusted.contains { $0.id == id })
        b.disconnect(); b.centralManager(c, didDisconnectPeripheral: p, error: nil)
        p.name = "PCR-NFCPRO"
        b.scan(); discover(p); b.finishDiscovery()
        precondition(b.connectionPrompt?.id == id)
        b.cancelConnectionPrompt(); b.connectionPromptDidDisappear()
        precondition(!b.scanning)
        // A matching broadcast name with another UUID must not inherit trust.
        saved.autoScan = true; precondition(saved.save())
        let unknown = PCRBluetooth(); unknown.setForeground(true)
        let cu = CBCentralManager.latest!; unknown.centralManagerDidUpdateState(cu)
        let clone = CBPeripheral(name: "PCR-NFCPRO", services: [])
        unknown.centralManager(cu, didDiscover: clone, advertisementData: [CBAdvertisementDataLocalNameKey: "PCR-NFCPRO"], rssi: -20)
        unknown.finishDiscovery()
        precondition(!unknown.active && unknown.connectionPrompt?.id == clone.identifier)
        unknown.cancelConnectionPrompt()
        precondition(BLEPreferences.load().trusted == saved.trusted, "Sheet cancellation never revokes trust")
        // Advanced settings uses the existing explicit confirmation API.
        var custom = BLEProfile.builtin
        custom.id = UUID(); custom.name = "Connection only"; custom.adapterID = "connect-only"
        precondition(unknown.addProfile(custom) == nil)
        unknown.scan()
        unknown.centralManager(cu, didDiscover: p, advertisementData: [CBAdvertisementDataLocalNameKey: "PCR-NFCPRO"], rssi: -50)
        unknown.confirmConnection(unknown.devices[0], profileID: custom.id, remember: true)
        precondition(BLEPreferences.load().trusted.first?.profileID == custom.id && cu.connections == 1)
        precondition(p.writes.isEmpty && p.reads.isEmpty)
        unknown.setForeground(false)
        unknown.centralManager(cu, didDisconnectPeripheral: p, error: nil)
        CBCentralManager.authorization = .denied
        let denied = PCRBluetooth(); denied.setForeground(true)
        precondition(!denied.scanning)
        CBCentralManager.authorization = .allowedAlways
        denied.setForeground(false); denied.setForeground(true)
        let ca = CBCentralManager.latest!; denied.centralManagerDidUpdateState(ca)
        precondition(denied.scanning)
        denied.setForeground(false)
        BLEPreferences().save()
        print("PASS: recovery cycles, duplicate state, delayed close, UUID-only saved trust, prompt cancellation, explicit revocation, profile persistence and authorization recovery; synthetic transport only.")
    }
    static func presentationChecks() {
        BLEPreferences().save()
        let b = PCRBluetooth(); b.setForeground(true)
        let c = CBCentralManager.latest!; b.centralManagerDidUpdateState(c)
        let p = CBPeripheral(name: "PCR-NFCPRO", services: [])
        func discover() {
            b.centralManager(c, didDiscover: p, advertisementData: [CBAdvertisementDataLocalNameKey: "PCR-NFCPRO"], rssi: -40)
        }
        // Exercise every shared root lease against the actual production coordinator.
        for key in ["root.photos", "root.nfc", "root.logs", "root.profile", "device.settings", "device.profile", "library.modal", "wallpaper.photos"] {
            b.scan(); b.setPresentationBlocker(key, active: true); discover(); b.finishDiscovery()
            precondition(b.connectionPrompt == nil && !b.active && p.writes.isEmpty)
            b.finishPresentationBlocker(key)
            precondition(b.connectionPrompt?.id == p.identifier, "Modal dismissal resumes, never cancels discovery")
            b.connectionPromptDidAppear()
            b.setPresentationBlocker(key, active: true)
            precondition(b.connectionPrompt == nil)
            b.finishPresentationBlocker(key)
            precondition(b.connectionPrompt == nil, "Old sheet must finish dismissal first")
            b.connectionPromptDidDisappear()
            precondition(b.connectionPrompt?.id == p.identifier, "Programmatic deferral is not user cancellation")
            b.cancelConnectionPrompt(); b.connectionPromptDidDisappear()
        }
        b.scan(); b.setPresentationBlocker("root.photos", active: true)
        b.setPresentationBlocker("device.profile", active: true)
        discover(); b.finishDiscovery()
        b.finishPresentationBlocker("root.photos")
        precondition(b.connectionPrompt == nil, "Nested lease cannot release another modal")
        b.finishPresentationBlocker("device.profile")
        precondition(b.connectionPrompt != nil)
        b.connectionPromptDidAppear()
        b.connectionPrompt = nil // Interactive swipe, unlike a programmatic close.
        b.connectionPromptDidDisappear(); b.finishDiscovery()
        precondition(b.connectionPrompt == nil, "Real user dismissal suppresses current cycle")
        b.scan(); b.setPresentationBlocker("root.photos", active: true); discover(); b.finishDiscovery()
        b.scan() // Replaced scan invalidates the queued stale device.
        b.finishPresentationBlocker("root.photos")
        precondition(b.connectionPrompt == nil && b.devices.isEmpty)
        discover(); b.finishDiscovery(); b.connectionPromptDidAppear()
        b.setPresentationBlocker("root.logs", active: true)
        b.confirmConnection(b.devices[0], profileID: BLEProfile.builtin.id, remember: true)
        b.connectionPromptDidDisappear(); b.finishPresentationBlocker("root.logs")
        precondition(b.active && b.connectionPrompt == nil && c.cancellations == 0)
        precondition(BLEPreferences.load().trusted.contains { $0.id == p.identifier })
        precondition(p.writes.isEmpty && p.reads.isEmpty, "Presentation never issues business commands")
        b.disconnect(); b.centralManager(c, didDisconnectPeripheral: p, error: nil)
        b.setForeground(false); b.setForeground(true); discover(); b.finishDiscovery()
        precondition(b.active && b.connectionPrompt == nil, "Saved trust is not re-confirmed after modal return")
        b.setForeground(false); BLEPreferences().save()
        print("PASS: root Photos/NFC/log/profile/settings/file leases, nested release, stale candidate, real swipe cancel, deferred/programmatic close and persisted trust; production coordinator with host transport.")
    }
    static func retryBoundChecks() {
        let p = CBPeripheral(name: "PCR-NFCPRO", services: [])
        var saved = BLEPreferences()
        saved.trusted = [BLETrust(id: p.identifier, profileID: BLEProfile.builtin.id)]
        saved.save()
        let b = PCRBluetooth(); b.setForeground(true)
        let c = CBCentralManager.latest!; b.centralManagerDidUpdateState(c)
        for attempt in 1...3 {
            precondition(b.scanning)
            b.centralManager(c, didDiscover: p, advertisementData: [CBAdvertisementDataLocalNameKey: "PCR-NFCPRO"], rssi: -40)
            b.finishDiscovery()
            precondition(b.active && c.connections == attempt && b.connectionPrompt == nil)
            b.centralManager(c, didFailToConnect: p, error: nil)
            RunLoop.main.run(until: Date().addingTimeInterval(attempt < 3 ? Double(attempt * 2) + 0.1 : 0.1))
        }
        precondition(!b.active && !b.scanning && c.connections == 3 && b.connectionPrompt == nil)
        b.centralManagerDidUpdateState(c); b.enterDeviceFlow()
        // Page entry must not reopen scanning after budget exhaustion either.
        precondition(!b.scanning && c.connections == 3)
        b.setForeground(false)
        BLEPreferences().save()
    }
    static func main() {
        // Host executable's own defaults domain only; preserve any pre-existing fixture.
        let key = "linkcard.ble.preferences.v1"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original = original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        persistenceFailureChecks()
        recoveryChecks()
        presentationChecks()
        retryBoundChecks()
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
        manual.enterDeviceFlow()
        precondition(!manual.active && !manual.scanning && cm.scans == scans && cm.connections == 1)
        manual.setForeground(false); manual.setForeground(true); manual.enterDeviceFlow()
        precondition(!manual.active && manual.scanning && cm.scans == scans + 1 && cm.connections == 1)
        precondition(manual.lastDisconnectReason == .user)
        manual.setForeground(false)

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
