# SPDX-License-Identifier: GPL-3.0-or-later
"""Source-contract regressions only, not an iOS/CoreBluetooth execution test."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
BLE = (ROOT / 'LinkCard/PCRBluetooth.swift').read_text()
PROTO = (ROOT / 'LinkCard/PCRProtocol.swift').read_text()

class NFCProSafety(unittest.TestCase):
    def test_not_text_model(self):
        names = PROTO.split('static let textNames:', 1)[1].split('static func allowsText', 1)[0]
        self.assertNotIn('NFCPRO', names)
        self.assertIn('["PCR-NFCPRO(BLE)", "PCR-NFCPRO"].contains(advertisedName)', PROTO)
        self.assertIn('canQuery = PCRRoute.allowsText(selected?.name ?? "")', BLE)

    def test_only_four_standard_fields(self):
        fields = PROTO.split('static let fields:', 1)[1].split('static func displayValue', 1)[0]
        self.assertEqual(re.findall(r'"(2A[0-9A-F]{2})"', fields), ['2A24', '2A27', '2A28', '2A29'])
        self.assertNotIn('"2A25"', BLE + PROTO)
        self.assertIn('BLEProfile.sameUUID($0.uuid.uuidString, "180A")', BLE)
        self.assertIn('$0.properties.contains(.read)', BLE)

    def test_user_action_only(self):
        self.assertEqual(BLE.count('readDeviceInformation()'), 1)
        self.assertEqual(BLE.count('peripheral.readValue(for:'), 1)
        self.assertIn('guard connected, canReadDeviceInformation, !busy, !closing', BLE)
        self.assertIn('guard busy, characteristic === pendingInformation', BLE)
        body = BLE.split('func readDeviceInformation()', 1)[1].split('func readVersion()', 1)[0]
        self.assertNotIn('writeValue', body)
        self.assertNotIn('readVersion()', body)
        self.assertIn('arm(4)', body)
        self.assertIn('disconnect(', body)

    def test_no_new_business_probe(self):
        self.assertEqual(BLE.count('Data("PCRPANDA?\\r\\n".utf8)'), 1)
        for forbidden in ('SAMConfiguration', 'getFirmwareVersion', 'BLEVERSION?', 'URLSession', 'print(', 'UserDefaults'):
            self.assertNotIn(forbidden, BLE)
        self.assertNotIn('PCRPN53xReply()', BLE)

    def test_bounded_display_no_raw_diagnostics(self):
        self.assertIn('data.count <= 128', PROTO)
        self.assertIn('encoding: .utf8', PROTO)
        self.assertIn('CharacterSet.controlCharacters', PROTO)
        self.assertIn('generalCategory != .format', PROTO)
        self.assertIn('value.prefix(80)', PROTO)
        self.assertNotIn('localizedDescription', BLE)

    def test_callbacks_isolated_and_disconnect_clears(self):
        callback = BLE.split('didUpdateValueFor characteristic:', 1)[1]
        self.assertLess(callback.index('if readingDeviceInformation'), callback.index('try parser.feed'))
        disconnect = BLE.split('func disconnect(', 1)[1].split('func readDeviceInformation()', 1)[0]
        self.assertIn('informationQueue = []; pendingInformation = nil; informationCharacteristics = []', disconnect)
        self.assertIn('readingDeviceInformation = false', disconnect)

if __name__ == '__main__':
    unittest.main()
