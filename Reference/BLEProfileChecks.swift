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
        print("PASS: BLE profile validation, UUID aliases, adapters and format v1. No CoreBluetooth exercised.")
    }
}
