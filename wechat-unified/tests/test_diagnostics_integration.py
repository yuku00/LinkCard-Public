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

    def test_failed_service_metadata_wiring_and_bounds(self):
        host = (ROOT / 'Sources/WUHostService.m').read_text()
        messages = (ROOT / 'Sources/Messages.m').read_text()
        diag = (ROOT / 'Sources/WUDiagnostics.m').read_text()
        build = (ROOT / 'tools/build.sh').read_text()
        release = (ROOT / 'tools/release.py').read_text()
        metadata = host.split('void WURecordAccountServiceMismatch', 1)[1]
        self.assertIn('if((failure || accountException) && mgr) WURecordAccountServiceMismatch(mgr,providerPath)', messages)
        for text in ('object_getClass(service)', 'class_getSuperclass(cursor)', 'method_getTypeEncoding(method)', 'WUProviderActive', 'WUProviderCurrent', 'WUProviderLegacy', 'WUDiagnosticRateAllow(&rate', 'className.length>96', 'type.length>96'):
            self.assertIn(text, metadata)
        for forbidden in ('description', 'objc_msgSend', 'writeToFile', 'NSUserDefaults', 'NSURL', 'm_nsUsrName'):
            self.assertNotIn(forbidden, metadata)
        self.assertIn('WUAccountServiceDiagnosticSnapshot()', diag)
        self.assertIn('摘要可能包含账号服务的运行时类名', diag)
        self.assertIn('sh tools/test_host_service.sh', build)
        for name in ('tests/host_service_native.m', 'tools/test_host_service.sh', 'Sources/WUHostService.m'):
            self.assertIn(name, release)

    def test_result_sharing_does_not_promise_query_is_absent(self):
        source = (ROOT / 'Sources/WUDiagnostics.m').read_text()
        self.assertNotIn('仅分享你选择的这一条，不包含搜索词', source)
        self.assertIn('结果本身可能包含搜索词', source)

if __name__ == '__main__':
    unittest.main()
