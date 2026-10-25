// SPDX-License-Identifier: GPL-3.0-or-later
// Optional macOS offline check (not a BLE/hardware test):
// swiftc LinkCard/PCRProtocol.swift LinkCard/BLEProfiles.swift Reference/BLEProfileChecks.swift -o /tmp/ble-profile-checks && /tmp/ble-profile-checks
import Foundation

@main struct BLEProfileChecks {
    static func main() {
        for value in ["FF00", "ff01", "12345678", "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"] { precondition(BLEProfile.validUUID(value)) }
        for value in ["", "FF0", "FF000", "GG00", " FF00", "FF00\n", "FF00\r\n", "../../FF00", "0xFF00"] { precondition(!BLEProfile.validUUID(value)) }
        precondition(BLEProfile.builtin.validationError == nil)
        var profile = BLEProfile(id: UUID(), name: "自定义 PCR-NFCPRO", namePrefix: "TEST", serviceUUID: "", writeUUID: "", notifyUUID: "", adapterID: "connect-only")
        precondition(profile.validationError == nil)
        precondition(profile.channels.isEmpty)
        precondition(!ConnectOnlyAdapter().permitsVersion(advertisedName: "PcrGP_V2.0"))
        precondition(!PCRTextAdapter().permitsVersion(advertisedName: "PCR-NFCPRO(BLE)"))
        precondition(PCRTextAdapter().permitsVersion(advertisedName: "PcrGP_V2.0"))
        profile.adapterID = "arbitrary-script"
        precondition(profile.validationError != nil)
        profile.adapterID = "pcr-text-v1"
        precondition(profile.validationError != nil)
        profile.serviceUUID = "FF00"; profile.writeUUID = "FF02"; profile.notifyUUID = "FF01"
        precondition(profile.validationError == nil)
        profile.serviceUUID = "0000FF00-0000-1000-8000-00805F9B34FB"
        precondition(profile.validationError == nil)
        precondition(profile.matches(name: "", services: ["FF00"]))
        profile.adapterID = "connect-only"
        profile.notifyUUID = "0000FF02-0000-1000-8000-00805F9B34FB"
        precondition(profile.validationError != nil)
        profile.notifyUUID = "FF01"; profile.writeUUID = ""
        precondition(profile.validationError != nil)
        profile = BLEProfile.builtin; profile.name = "changed"
        precondition(profile.validationError != nil)
        let preferences = BLEPreferences()
        let data = try! JSONEncoder().encode(preferences)
        let decoded = try! JSONDecoder().decode(BLEPreferences.self, from: data)
        precondition(decoded.formatVersion == 1 && decoded.trusted.isEmpty && decoded.autoScan && decoded.showDiscoveryPrompt)
        let suiteName = "LinkCard.BLEProfileChecks." + UUID().uuidString
        let store = UserDefaults(suiteName: suiteName)!
        defer { store.removePersistentDomain(forName: suiteName) }
        let key = "linkcard.ble.preferences.v1"
        var saved = BLEPreferences()
        let deviceID = UUID()
        saved.trusted = [BLETrust(id: deviceID, profileID: BLEProfile.builtin.id)]
        saved.autoScan = false; saved.showDiscoveryPrompt = false
        precondition(saved.save(to: store))
        let restored = BLEPreferences.load(from: store)
        precondition(restored.trusted == saved.trusted && restored.profiles == saved.profiles)
        precondition(!restored.autoScan && !restored.showDiscoveryPrompt && restored.restorationWarning == nil)
        let goodData = store.data(forKey: key)!
        let encoded = try! JSONSerialization.jsonObject(with: goodData) as! [String: Any]
        precondition(encoded["restorationWarning"] == nil)
        for bad in [Data("invalid".utf8), Data(repeating: 0, count: 131073)] {
            store.set(bad, forKey: key)
            var failed = BLEPreferences.load(from: store)
            precondition(failed.restorationWarning != nil && !failed.autoScan && !failed.showDiscoveryPrompt)
            failed.autoScan = true
            precondition(!failed.save(to: store) && store.data(forKey: key) == bad)
        }
        var unknownVersion = encoded; unknownVersion["formatVersion"] = 2
        let future = try! JSONSerialization.data(withJSONObject: unknownVersion)
        store.set(future, forKey: key)
        precondition(BLEPreferences.load(from: store).restorationWarning != nil)
        precondition(store.data(forKey: key) == future)
        var missingOptional = encoded; missingOptional.removeValue(forKey: "showDiscoveryPrompt")
        store.set(try! JSONSerialization.data(withJSONObject: missingOptional), forKey: key)
        let migrated = BLEPreferences.load(from: store)
        precondition(migrated.restorationWarning == nil && !migrated.showDiscoveryPrompt && migrated.trusted == saved.trusted)
        var missingIdentity = encoded; missingIdentity.removeValue(forKey: "trusted")
        let incomplete = try! JSONSerialization.data(withJSONObject: missingIdentity)
        store.set(incomplete, forKey: key)
        let incompleteRestore = BLEPreferences.load(from: store)
        precondition(incompleteRestore.restorationWarning != nil && !incompleteRestore.save(to: store))
        precondition(store.data(forKey: key) == incomplete)
        var brokenBinding = saved
        brokenBinding.trusted[0].profileID = UUID()
        store.set(try! JSONEncoder().encode(brokenBinding), forKey: key)
        precondition(BLEPreferences.load(from: store).restorationWarning != nil)
        store.set(goodData, forKey: key)
        precondition(BLEPreferences.load(from: store).trusted.first?.profileID == BLEProfile.builtin.id)
        print("PASS: profile validation, stable UUID binding, actual UserDefaults save/load, optional-field migration, corrupt/future/invalid binding preservation. No CoreBluetooth exercised.")
    }
}
