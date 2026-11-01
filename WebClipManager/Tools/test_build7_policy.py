"""Synthetic policy regression; NOT a Seatbelt/device-success test."""
from pathlib import Path
import plistlib
r = Path(__file__).resolve().parents[1]
e = plistlib.loads((r/'Config/TrollStore.entitlements').read_bytes())
assert e['platform-application'] is True
assert e['com.apple.private.security.container-required'] is False, 'build6 explicit container remains'
assert e['com.apple.private.security.no-container'] is True
assert e['com.apple.security.app-sandbox'] is False
assert len(e) == 9
s = (r/'Sources/AppPaths.swift').read_text()
assert 'CFFIXED_USER_HOME' in s and 'TMPDIR' in s and 'O_NOFOLLOW' in s
assert 'org.example.WebClipManager' in s
main = (r/'Sources/main.swift').read_text()
assert main.index('AppPaths.prepare()') < main.index('StartupLog.record')
runtime = (r/'Sources/RuntimePermissions.m').read_text()
for name in ['SecTaskCreateFromSelf', 'SecTaskCopyValueForEntitlement', 'sandbox_check', 'file-read-data', 'file-read-metadata']:
    assert name in runtime
assert 'unknown' in runtime
# Synthetic reproduction of supplied metadata pattern; contains no user artifact.
paths = [{'stat': 0, 'realpath': 0, 'open': 1} for _ in range(2)]
assert all(p['stat'] == 0 and p['realpath'] == 0 and p['open'] == 1 for p in paths)
print('PASS: synthetic non-container policy, dedicated paths, runtime diagnostics contracts')
print('NOT TESTED: actual installed Seatbelt profile or device access')
