import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class AccountGenerationTest(unittest.TestCase):
    def test_fingerprint_transition_and_native_coverage(self):
        source = (ROOT / 'Sources/Messages.m').read_text()
        self.assertIn('CCHmac(kCCHmacAlgSHA256', source)
        self.assertNotIn('static NSString *lastAccount;', source)
        self.assertIn('lastAccountFingerprint=fingerprint', source)
        native = (ROOT / 'tests/host_service_native.m').read_text()
        for case in ('generation==g+1', 'BadProvider', 'BadContact', 'current=nil', 'legacy=nil'):
            self.assertIn(case, native)

if __name__ == '__main__':
    unittest.main()
