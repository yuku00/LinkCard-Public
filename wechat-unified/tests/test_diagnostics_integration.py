import ast
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class DiagnosticsIntegrationTests(unittest.TestCase):
    def test_build_runs_and_release_includes_regressions(self):
        build = (ROOT / 'tools/build.sh').read_text()
        release = ast.parse((ROOT / 'tools/release.py').read_text())
        strings = {n.value for n in ast.walk(release) if isinstance(n, ast.Constant) and isinstance(n.value, str)}
        for test in ('tests/test_settings_search.py', 'tests/test_diagnostics_contract.py', 'tests/test_link_diagnostics.py', 'tests/diagnostic_ring.c'):
            self.assertIn(test, build)
            self.assertIn(test, strings)
        self.assertIn('build/diagnostic-ring-tests', build)

    def test_account_chain_records_only_fixed_first_failure(self):
        import re
        source = (ROOT / 'Sources/Messages.m').read_text()
        account = source.split('static NSString *Account(void) {', 1)[1].split('\nNSString *WUCurrentAccount', 1)[0]
        header = (ROOT / 'Sources/WUDiagnosticRing.h').read_text()
        diag = (ROOT / 'Sources/WUDiagnostics.m').read_text()
        enums = re.findall(r'WUDiagAccount\w+', header.split('} WUDiagnosticEvent;', 1)[0])
        self.assertEqual(len(enums), 11)
        for event in ('WUDiagAccountManagerClass', 'WUDiagAccountManagerMissing', 'WUDiagAccountSelfSignature', 'WUDiagAccountSelfMissing', 'WUDiagAccountNameSignature', 'WUDiagAccountNameInvalid', 'WUDiagAccountException'):
            self.assertIn(event, account)
        self.assertIn('if(failure) WURecordAccountDiagnosticEvent(failure)', account)
        self.assertIn('WUDiagnosticRateAllow(&rates[event],NSProcessInfo.processInfo.systemUptime)', diag)
        names = re.search(r'names=@\[(.*?)\];', diag, re.S).group(1)
        self.assertEqual(len(re.findall(r'@"(?:[^"\\\\]|\\\\.)*"', names)),
                         len(re.findall(r'WUDiag\w+', header.split('} WUDiagnosticEvent;', 1)[0])))
        self.assertIn('if((fingerprint || lastAccountFingerprint) && ![fingerprint isEqual:lastAccountFingerprint])', account)

    def test_result_sharing_does_not_promise_query_is_absent(self):
        source = (ROOT / 'Sources/WUDiagnostics.m').read_text()
        self.assertNotIn('仅分享你选择的这一条，不包含搜索词', source)
        self.assertIn('结果本身可能包含搜索词', source)

if __name__ == '__main__':
    unittest.main()
