"""Build10 static regression gates; NOT a real-device sandbox acceptance test."""
from pathlib import Path
import plistlib
r = Path(__file__).resolve().parents[1]
e = plistlib.loads((r/'Config/TrollStore.entitlements').read_bytes())
assert e['com.apple.private.security.container-required'] is False
assert e['com.apple.private.security.no-container'] is True
assert len(e) == 8
assert 'com.apple.security.app-sandbox' not in e
sources = '\n'.join(p.read_text() for p in (r/'Sources').glob('*') if p.is_file())
for forbidden in ['setenv(', 'unsetenv(', '@AppStorage', '@SceneStorage', 'UserDefaults.standard', 'chmod(', 'setuid(', 'posix_spawn(']:
    assert forbidden not in sources, forbidden
paths = (r/'Sources/AppPaths.swift').read_text()
assert 'ready = isContainer &&' in paths
assert 'createDirectory' not in paths
main = (r/'Sources/main.swift').read_text()
assert 'AppPaths.prepare()' not in main
startup = (r/'Sources/Startup.swift').read_text()
assert 'AppPaths.ready' not in startup
assert 'UITextView' in startup and 'isSelectable = true' in startup
assert 'UIPasteboard.general.string' in startup
assert 'Report(build: 10' in startup
assert 'RuntimePermissions.capture()' in startup and 'ReadAccess.diagnostics()' in startup
probe = (r/'Sources/RuntimePermissions.m').read_text()
assert 'typedef int (*SandboxCheck)(pid_t, const char *, int, ...)' in probe
assert 'SANDBOX_CHECK_NO_REPORT' in probe and '0x10000000' not in probe
assert 'path.UTF8String' in probe and 'filterType' in probe
for f in ['App.swift', 'Notes.swift', 'Interface.swift']:
    page = (r/'Sources'/f).read_text()
    assert 'if AppPaths.ready {' in page
    for forbidden in ['fileImporter(', 'fileExporter(', 'UTType', 'BackupDocument', 'NoteExportDocument']:
        assert forbidden not in page, (f, forbidden)
log = (r/'Sources/StartupLog.swift').read_text()
assert 'AppPaths' not in log and 'open(' not in log and 'build=10' in log
print('PASS: build10 single noncontainer profile; OS HOME untouched; structurally isolated file UI; runtime filter symbol')
