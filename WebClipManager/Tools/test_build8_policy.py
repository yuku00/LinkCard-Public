"""Build8 startup contract; static gate, not a device crash reproduction."""
from pathlib import Path
import plistlib
r = Path(__file__).resolve().parents[1]
e = plistlib.loads((r/'Config/TrollStore.entitlements').read_bytes())
assert e['com.apple.private.security.container-required'] == 'org.example.WebClipManager'
assert 'com.apple.private.security.no-container' not in e
assert 'com.apple.security.app-sandbox' not in e
assert len(e) == 7
paths = (r/'Sources/AppPaths.swift').read_text()
assert 'setenv(' not in paths and 'unsetenv(' not in paths
main = (r/'Sources/main.swift').read_text()
assert 'AppPaths.prepare()' not in main
startup = (r/'Sources/Startup.swift').read_text()
assert 'AppPaths.ready' not in startup
assert 'UITextView' in startup and 'isSelectable = true' in startup
assert 'UIPasteboard.general.string' in startup
assert 'RuntimePermissions.capture()' in startup and 'ReadAccess.diagnostics()' in startup
log = (r/'Sources/StartupLog.swift').read_text()
assert 'AppPaths' not in log and 'open(' not in log
assert 'build=8' in log
print('PASS: build8 container, no environment mutation, independent memory diagnostics')
