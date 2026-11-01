"""Build6 regression gate. Static only; real iOS MAC access requires device feedback."""
from pathlib import Path
import plistlib
r = Path(__file__).resolve().parents[1]
e = plistlib.loads((r/'Config/TrollStore.entitlements').read_bytes())
assert e.get('com.apple.private.security.storage.Safari') is True, 'Missing reviewed Safari storage candidate'
from entitlement_policy import validate_entitlements
validate_entitlements(e)
s = (r/'Sources/Repository.swift').read_text()
check = s.split('private func check(')[1].split('private func folder(')[0]
assert 'resourceValues' not in check, 'Foundation metadata preflight still gates actual open'
a = (r/'Sources/ReadAccess.swift').read_text()
assert 'O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC' in a
assert 'NSLocalizedDescriptionKey' not in a and 'NSFilePathErrorKey' not in a
assert 'uid: getuid(), euid: geteuid()' in a
assert 'underlyingPOSIX' in a and 'openErrno' in a
print('PASS build6 policy/read-only/redaction regression gate (not device MAC validation)')
