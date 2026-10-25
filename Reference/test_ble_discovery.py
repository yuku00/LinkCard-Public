# SPDX-License-Identifier: GPL-3.0-or-later
"""Source-contract checks only; no Swift compilation/CoreBluetooth execution."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
BLE = (ROOT / 'LinkCard/PCRBluetooth.swift').read_text()
PROFILES = (ROOT / 'LinkCard/BLEProfiles.swift').read_text()
UI = (ROOT / 'LinkCard/BLEPreferencesView.swift').read_text()

class BLEDiscoveryContracts(unittest.TestCase):
    def test_foreground_authorization_and_no_private_power_api(self):
        self.assertIn('CBCentralManager.authorization == .allowedAlways', BLE)
        self.assertIn('CBCentralManagerOptionShowPowerAlertKey: false', BLE)
        self.assertIn('guard foreground, let central', BLE)
        for forbidden in ['setPowered', 'BluetoothManager', 'IOBluetooth', 'performSelector']:
            self.assertNotIn(forbidden, BLE)
        self.assertIn('.bleDiscoveryHost(ble)', (ROOT/'LinkCard/ContentView.swift').read_text())
        self.assertIn('case .background: ble.setForeground(false)', UI)
        self.assertIn('case .inactive: break', UI)

    def test_no_business_writes_in_auto_discovery(self):
        automatic = BLE[BLE.index('private func scanAutomatically'):BLE.index('func stopScan')]
        for forbidden in ['writeValue(', 'readValue(', 'readVersion(', 'readDeviceInformation(']:
            self.assertNotIn(forbidden, automatic)
        self.assertEqual(BLE.count('Data("PCRPANDA?\\r\\n".utf8)'), 1)
        self.assertEqual(BLE.count('peripheral.writeValue('), 2)

    def test_binding_and_explicit_priority_not_rssi(self):
        finish = BLE[BLE.index('func finishDiscovery'):BLE.index('private func scheduleRetry')]
        self.assertIn('preferences.trusted.first', finish)
        self.assertIn('$0.id == saved.id', finish)
        self.assertIn('$0.id == trust.profileID', finish)
        self.assertNotIn('.rssi', finish.lower())
        self.assertIn('automaticTarget == saved.id', finish)
        self.assertIn('if remember {', BLE)
        self.assertIn('BLETrust(id: device.id, profileID: profile.id)', BLE)

    def test_prompt_toggle_does_not_revoke_autoconnect(self):
        method = BLE[BLE.index('func setDiscoveryPrompt'):BLE.index('func addProfile')]
        self.assertNotIn('trusted', method)
        self.assertNotIn('autoScan =', method)
        finish = BLE[BLE.index('func finishDiscovery'):BLE.index('private func scheduleRetry')]
        self.assertLess(finish.index('connect(device)'), finish.index('showDiscoveryPrompt'))
        self.assertIn('@State private var remember = false', UI)
        self.assertIn('if !value { dismissConnectionPrompt() }', method)
        self.assertIn('if !promptDismissalIsProgrammatic { cancelConnectionPrompt() }', BLE)
        self.assertIn('.sheet(item: $ble.connectionPrompt, onDismiss:', UI)
        self.assertEqual(UI.count('ble.connectionPromptDidDisappear()'), 1)
        host = UI.split('private struct BLEDiscoveryHost:')[1].split('private struct BLEConnectionConfirmation:')[0]
        self.assertNotIn('.onDisappear', host)
        self.assertNotIn('.onDisappear { ble.cancelConnectionPrompt()', UI)
        confirm = BLE[BLE.index('func confirmConnection'):BLE.index('func resumeDiscovery')]
        self.assertLess(confirm.index('dismissConnectionPrompt()'), confirm.index('connect(device)'))
        dismiss = BLE[BLE.index('private func dismissConnectionPrompt'):BLE.index('func connectionPromptDidDisappear')]
        self.assertLess(dismiss.index('promptDismissalIsProgrammatic = true'), dismiss.index('connectionPrompt = nil'))

    def test_cancellation_and_timeout_boundaries(self):
        self.assertIn('if suppressSession { sessionSuppressed = true; retryAfterDisconnect = false }', BLE)
        self.assertIn('attempts < 3', BLE)
        self.assertIn('Double(attempts * 2)', BLE)
        self.assertIn('arm(12)', BLE)
        self.assertIn('arm(15)', BLE)
        self.assertIn('self?.connectionFailed(', BLE)
        request = BLE[BLE.index('func requestConnection'):BLE.index('func cancelConnectionPrompt')]
        self.assertIn('stopScan()', request)
        self.assertIn('sessionSuppressed = true', request)
        self.assertIn('private func connect(', BLE)

    def test_profile_validation_and_command_gate(self):
        self.assertIn('DeviceAdapters.adapter(adapterID) != nil', PROFILES)
        self.assertIn('DeviceAdapters.pcrChannels.contains(', PROFILES)
        self.assertIn('func permitsVersion(advertisedName: String) -> Bool { false }', PROFILES)
        self.assertIn('canQuery = PCRRoute.allowsText(selected?.name ?? "")', BLE)
        self.assertIn('&& DeviceAdapters.adapter(connectionProfile.adapterID)?.permitsVersion', BLE)
        self.assertIn('for map in connectionProfile.channels', BLE)
        self.assertIn('write !== notify', BLE)
        self.assertIn('write.properties.contains(.write)', BLE)
        self.assertIn('notify.properties.contains(.notify)', BLE)
        self.assertNotIn('profile.name)', BLE)

    def test_persistence_limits_version_and_privacy(self):
        self.assertIn('formatVersion == 1', PROFILES)
        self.assertIn('value.trusted.count <= 100', PROFILES)
        self.assertIn('preferences.trusted.count < 100', BLE)
        for source in [BLE, PROFILES]:
            for forbidden in ['print(', 'NSLog(', 'URLSession', 'JavaScriptCore', 'WKWebView']:
                self.assertNotIn(forbidden, source)
        self.assertIn('trust.id.uuidString.suffix(4)', UI)

    def test_disabling_scan_preserves_connection_deadline(self):
        stop = BLE[BLE.index('func stopScan()'):BLE.index('private func connect(')]
        self.assertIn('let wasScanning = scanning', stop)
        self.assertIn('if wasScanning { deadline?.cancel() }', stop)

    def test_uuid_full_match_and_alias_rejection(self):
        self.assertIn('return range == (value.startIndex..<value.endIndex)', PROFILES)
        self.assertIn('Self.canonicalUUID(writeUUID) != Self.canonicalUUID(notifyUUID)', PROFILES)
        self.assertIn('write !== notify', BLE)

    def test_ui_all_connections_confirmed(self):
        views = (ROOT/'LinkCard/LocalDeviceViews.swift').read_text()
        self.assertIn('ble.requestConnection(device)', views)
        self.assertNotIn('ble.connect(device)', views)
        self.assertIn('ble.confirmConnection(selected, profileID: profileID, remember: remember)', UI)
        self.assertIn('ble.cancelConnectionPrompt()', UI)

if __name__ == '__main__':
    unittest.main()
