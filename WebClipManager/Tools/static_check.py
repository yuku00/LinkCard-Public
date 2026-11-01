"""Static packaging/safety checks only; does not compile Swift or run XCTest."""
from pathlib import Path
import plistlib
import json
import struct
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
from entitlement_policy import validate_entitlements, self_test, BUILD
self_test()
assert str(project['settings']['base']['CURRENT_PROJECT_VERSION']) == BUILD
props = project['targets']['WebClipManager']['info']['properties']
assert props['UIFileSharingEnabled'] is False and props['LSSupportsOpeningDocumentsInPlace'] is False
with (root / 'Config/TrollStore.entitlements').open('rb') as f:
    validate_entitlements(plistlib.load(f))
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
assert 'documents: files.documents' in (root / 'Sources/DocumentUI.swift').read_text()
assert workflow['on']['workflow_dispatch']['inputs']['sign_for_trollstore']['default'] == 'false'
steps = workflow['jobs']['build']['steps']
assert any('ldid -SConfig/TrollStore.entitlements' in s.get('run', '') and 'sign_for_trollstore' in s.get('if', '') for s in steps)
assert any('assert actual == expected' in s.get('run', '') for s in steps)
assert project['targets']['WebClipManager']['settings']['base']['ASSETCATALOG_COMPILER_APPICON_NAME'] == 'AppIcon'
icon_root = root / 'Assets.xcassets/AppIcon.appiconset'
icon_manifest = json.loads((icon_root / 'Contents.json').read_text())
allowed_icons = set()
for entry in icon_manifest['images']:
    size = int(float(entry['size'].split('x')[0]) * int(entry['scale'][0]))
    assert size in {20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024}
    assert entry['filename'] == f'AppIcon-{size}.png'
    path = icon_root / entry['filename']
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    width, height, depth, color = struct.unpack_from('>IIBB', data, 16)
    assert (width, height, depth, color) == (size, size, 8, 2), 'Require opaque RGB icon'
    allowed_icons.add(path)
assert len(allowed_icons) == 13
for path in root.rglob('*'):
    if path.is_file():
        assert not path.is_symlink()
        if path.suffix.lower() == '.png':
            assert path in allowed_icons, 'Only reviewed AppIcon PNGs may be included'
        else:
            assert path.suffix.lower() not in {'.zip', '.ipa', '.webclipbackup', '.jpg', '.jpeg', '.heic', '.sqlite', '.db', '.mobileprovision', '.p12'}
print('PASS: YAML structure, manual-only workflow, minimal entitlement, source boundaries, reviewed AppIcons only; no user archives/media')
print('NOT RUN: Swift compilation, XCTest, simulator, signing, installation, real-device permissions/deletion')
