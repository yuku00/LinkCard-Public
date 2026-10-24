# SPDX-License-Identifier: GPL-3.0-or-later
"""Reference scheduling model + source guards, NOT a CoreBluetooth runtime test."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class Session:
    def __init__(self):
        self.active = True
        self.busy = False
        self.generation = 0
        self.sent = []
    def request(self, payload, limit):
        if not self.active or self.busy:
            return False
        if limit < 1:
            raise ValueError()
        self.busy = True
        self.sent = [payload[i:i+limit] for i in range(0, len(payload), limit)]
        return True
    def timeout(self):
        self.active = self.busy = False
        self.generation += 1
    def response(self, generation):
        return self.active and self.busy and generation == self.generation

class PCRSafetyTests(unittest.TestCase):
    def test_serial_request(self):
        s = Session()
        self.assertTrue(s.request(b'PCRPANDA?\r\n', 4))
        self.assertFalse(s.request(b'BLEVERSION?\r\n', 4))
        self.assertEqual(b''.join(s.sent), b'PCRPANDA?\r\n')
        self.assertTrue(all(len(x) <= 4 for x in s.sent))
    def test_timeout_stale_response(self):
        s = Session(); s.request(b'x', 1); generation = s.generation
        s.timeout()
        self.assertFalse(s.response(generation))
        self.assertFalse(s.request(b'x', 1))
    def test_cancel_is_terminal(self):
        s = Session(); s.timeout()
        self.assertFalse(s.request(b'x', 1))
    def test_no_zero_limit(self):
        with self.assertRaises(ValueError): Session().request(b'x', 0)
    def test_transport_source_guards(self):
        text = (ROOT/'LinkCard/PCRBluetooth.swift').read_text()
        self.assertEqual(text.count('Data("PCRPANDA?\\r\\n".utf8)'), 1)
        for guard in ['maximumWriteValueLength', 'canSendWriteWithoutResponse',
                      'didWriteValueFor', 'arm(4)', 'arm(15)', 'arm(12)',
                      'characteristic === rx, busy, !closing', '!busy']:
            self.assertIn(guard, text)
        self.assertNotIn('BLEVERSION?', text)
        self.assertNotIn('URLSession', text)
        self.assertNotIn('print(', text)
    def test_file_safety_guards(self):
        text = (ROOT/'LinkCard/LocalCardLibrary.swift').read_text()
        for guard in ['.completeFileProtection', 'isExcludedFromBackup = true',
                      'read(upToCount: limit + 1)', 'NSFileCoordinator',
                      'isSymbolicLink', 'SHA256.hash', 'UUID()', 'cleanName']:
            self.assertIn(guard, text)
        self.assertNotIn('URLSession', text)
        self.assertNotIn('print(', text)
    def test_entitlements_unchanged(self):
        import plistlib
        ent = plistlib.loads((ROOT/'LinkCard/LinkCard.entitlements').read_bytes())
        self.assertEqual(ent, {'com.apple.developer.nfc.readersession.formats': ['TAG']})
        info = plistlib.loads((ROOT/'LinkCard/Info.plist').read_bytes())
        self.assertIn('NSBluetoothAlwaysUsageDescription', info)

if __name__ == '__main__': unittest.main()
