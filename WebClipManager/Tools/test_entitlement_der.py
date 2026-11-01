"""Regression for actual ldid Boolean encoding; no entitlement policy relaxation."""
import unittest
from entitlement_policy import decode_der


class DERBooleanTests(unittest.TestCase):
    def test_real_ldid_signature(self):
        # Slot 7 extracted from the existing build3 ldid-signed executable.
        raw = bytes.fromhex('312c302a0c25636f6d2e6170706c652e707269766174652e73656375726974792e6e6f2d73616e64626f78010101')
        self.assertEqual(decode_der(raw), {'com.apple.private.security.no-sandbox': True})

    def test_boolean_encodings(self):
        for encoded, expected in [('00', False), ('01', True), ('ff', True)]:
            self.assertEqual(decode_der(bytes.fromhex('310830060c01610101' + encoded)), {'a': expected})

    def test_invalid_inputs(self):
        for raw in ['310830060c0161010102', '310830060c016101017f',
                    '310930070c016101020001', '310730050c01610100',
                    '310830060c01610101', '310830060c016101010100',
                    '311030060c016101010130060c0161010101']:
            with self.subTest(raw=raw), self.assertRaises(AssertionError):
                decode_der(bytes.fromhex(raw))


if __name__ == '__main__':
    unittest.main()
