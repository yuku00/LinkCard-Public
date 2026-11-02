"""Build12 architectural regression checks; not a device sandbox proof."""
from pathlib import Path
import plistlib
from entitlement_policy import validate_entitlements
r = Path(__file__).resolve().parents[1]
e = plistlib.loads((r/'Config/TrollStore.entitlements').read_bytes())
validate_entitlements(e)
assert e['com.apple.private.security.container-required'] is False
assert e['com.apple.private.security.no-container'] is True
ui = (r/'Sources/BusinessUI.swift').read_text()
assert 'UIHostingController' not in ui and 'SwiftUI' not in ui
assert 'window.rootViewController = BusinessTabs()' in ui
assert 'window.makeKeyAndVisible()' in ui
assert 'try await repository.scan()' in ui and 'try AppleNotesStore.load()' in ui
assert 'UIDocumentPickerViewController(forExporting:' in ui
repo = (r/'Sources/Repository.swift').read_text()
assert 'HelperReader.scan()' not in repo
assert 'guard root != Self.deviceRoot' not in repo
assert 'return try ReadAccess.entries' not in repo  # enumeration is parsed, not returned as fake clips
assert 'let entries = try ReadAccess.entries(root)' in repo
assert '未删除：' in repo
startup = (r/'Sources/Startup.swift').read_text().split('final class StartupViewController')[0]
assert 'BusinessSceneDelegate.self' in startup
assert 'StartupViewController()' not in startup
workflow = (r/'.github/workflows/build.yml').read_text()
assert 'Helper/main.m -o' not in workflow and 'ldid -SConfig/Helper.entitlements' not in workflow
for forbidden in ['setenv(', 'setuid(', 'setgid(', 'persona_np', 'system(', 'posix_spawn']:
    assert forbidden not in ui
stage = (r/'Sources/ExportStaging.swift').read_text()
assert 'openat(dirFD' in stage and 'O_EXCL | O_NOFOLLOW' in stage and '0o600' in stage
assert 'unlinkat(dirFD' in stage and 'for name in Array(owned.keys)' in stage
print('PASS build12: direct read, UIKit scene root, exact build9 permissions, owned export files, deletion disabled')
