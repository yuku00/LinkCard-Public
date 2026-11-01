from pathlib import Path
import plistlib
from entitlement_policy import validate_entitlements, self_test
r=Path(__file__).resolve().parents[1]
self_test();validate_entitlements(plistlib.loads((r/'Config/TrollStore.entitlements').read_bytes()))
h=plistlib.loads((r/'Config/Helper.entitlements').read_bytes())
assert h['com.apple.private.security.no-container'] is True
assert h['com.apple.private.security.container-required'] is False
assert len(h)==8 and 'com.apple.private.persona-mgmt' not in h
helper=(r/'Helper/main.m').read_text(); client=(r/'Sources/HelperClient.c').read_text()
for forbidden in ['system(', 'popen(', 'setuid(', 'setgid(', 'persona_np', 'unlink(', 'remove(', 'chmod(', 'execve(']:
 assert forbidden not in helper+client, forbidden
assert 'SwiftUI' not in helper and 'O_NOFOLLOW' in helper and 'openat(' in helper
assert 'argc != 2' in helper and 'webclip-list' in helper
assert 'CAP + 1' in client and 'ETIMEDOUT' in client and 'WNOHANG' in client
assert 'AppleNotesStore.load()' not in (r/'Sources/Notes.swift').read_text()
assert 'HelperReader.scan()' in (r/'Sources/Repository.swift').read_text()
assert 'setenv(' not in ''.join(f.read_text() for f in (r/'Sources').glob('*') if f.is_file())
print('PASS: build11 fixed scope, split profiles, no elevation, no automatic Notes read')
