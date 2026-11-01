"""Static packaging/safety checks only; does not compile Swift or run XCTest."""
from pathlib import Path
import plistlib
import yaml

root = Path(__file__).resolve().parents[1]
project = yaml.safe_load((root / 'project.yml').read_text())
assert project['options']['deploymentTarget']['iOS'] == '16.0'
assert set(project['targets']) == {'WebClipManager', 'WebClipManagerTests'}
for target in project['targets'].values():
    for source in target['sources']:
        assert (root / (source if isinstance(source, str) else source['path'])).exists()
workflow = yaml.load((root / '.github/workflows/build.yml').read_text(), Loader=yaml.BaseLoader)
assert set(workflow['on']) == {'workflow_dispatch'}
assert workflow['permissions'] == {'contents': 'read'}
assert 'release' not in workflow['jobs']
with (root / 'Config/TrollStore.entitlements').open('rb') as f:
    assert plistlib.load(f) == {'com.apple.private.security.no-sandbox': True}
source = '\n'.join(p.read_text() for p in (root / 'Sources').glob('*.swift'))
for forbidden in ['removeItem(', 'removeFromDisk(', '.perform(', 'method_getImplementation', 'unsafeBitCast', 'URLSession', 'Process(', 'system(']:
    assert forbidden not in source, forbidden
assert '/var/mobile/Library/WebClips' in source
assert '未删除：' in source
interface = (root / 'Sources/Interface.swift').read_text()
notes = (root / 'Sources/Notes.swift').read_text()
assert 'class_getInstanceMethod' in interface and 'class_getClassMethod' in interface
for swift in (root / 'Sources').glob('*.swift'):
    if swift.name != 'Interface.swift':
        assert 'NSSelectorFromString' not in swift.read_text()
store = (root / 'Sources/AppleNotesStore.swift').read_text()
body = (root / 'Sources/AppleNoteBody.swift').read_text()
assert 'SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX' in store
assert 'sqlite3_backup_init(memory, "main", source, "main")' in store
assert 'sqlite3_backup_finish' in store and 'PRAGMA query_only=ON' in store
assert 'ZISPASSWORDPROTECTED' in store and 'ZCRYPTOTAG' in store
assert 'inflateInit2_' in body and 'case 5:' in body
assert 'confirmRead' in notes and 'loadAppleNotes()' in notes
assert {'sdk': 'libsqlite3.tbd'} in project['targets']['WebClipManager']['dependencies']
assert {'sdk': 'libz.tbd'} in project['targets']['WebClipManager']['dependencies']
assert (root / 'ThirdParty/AppleCloudNotesParser/LICENSE.txt').is_file()
assert (root / 'NOTICE').is_file()
assert 'startAccessingSecurityScopedResource' in notes and 'stopAccessingSecurityScopedResource' in notes
assert 'fileLimit + 1' in notes and 'totalLimit' in notes
assert 'documents: documents' in notes
assert workflow['on']['workflow_dispatch']['inputs']['sign_for_trollstore']['default'] == 'false'
steps = workflow['jobs']['build']['steps']
assert any('ldid -SConfig/TrollStore.entitlements' in s.get('run', '') and 'sign_for_trollstore' in s.get('if', '') for s in steps)
assert any('assert actual == expected' in s.get('run', '') for s in steps)
for path in root.rglob('*'):
    if path.is_file():
        assert path.suffix not in {'.zip', '.ipa', '.webclipbackup', '.png', '.jpg', '.mobileprovision', '.p12'}
print('PASS: YAML structure, manual-only workflow, minimal entitlement, source boundaries, no user archives/media')
print('NOT RUN: Swift compilation, XCTest, simulator, signing, installation, real-device permissions/deletion')
