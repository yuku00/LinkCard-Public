from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); a=(r/'NativeActions.inc').read_text(); q=(r/'ScopedPreview.inc').read_text()
assert 'InstallPreviewGuards' not in s and 'BlockPreview' not in s
for token in ('userToggledSelectionMode','selectAllItems','deselectAllItems','performRename:','performCreateFolder:','performGetInfo:','performDelete:', 'currentItemCollectionViewController'):
    assert token in s,token
assert 'Get(full,@"currentItemCollectionViewController")!=target' in s
assert 'canPerformAction:sel' in s
assert 'IsPaneListCell(v)' in a and 'InExperiment(collection.delegate)' in a
assert 'numberOfLines=3' in a and 'CGSizeMake(22,22)' in a
assert 'preferredLayoutAttributesFittingAttributes:' in a
assert 'CellStyleKey,nil' in a
assert '确认删除所选项目' in a and '无法恢复' in a
assert 'startAccessingSecurityScopedResource' in s and 'stopAccessingSecurityScopedResource' in q
assert 'NSFileCoordinatorReadingWithoutChanges' in q
for forbidden in ('valueForKey:', 'object_getIvar', 'ivar_getOffset', 'CGAffineTransform', 'removeItemAtURL:', 'moveItemAtURL:', 'copyItemAtURL:', 'UIPasteboard'):
    assert forbidden not in s+a+q,forbidden
print('PASS: scoped native actions/layout, actual selection target, provider-owned mutations, scoped coordinated QuickLook')
print('LIMIT: no safe selected-item URL bridge; cross-pane transfer intentionally absent, not simulated')
