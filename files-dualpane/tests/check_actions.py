from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); a=(r/'NativeActions.inc').read_text(); q=(r/'ScopedPreview.inc').read_text()
assert 'InstallPreviewGuards' not in s and 'BlockPreview' not in s
c=(r/'CompactCells.inc').read_text()
assert 'showActions' not in s and '左栏 · 操作' not in s
assert 'FPPaneMenu(self,0)' in s and 'FPPaneMenu(self,1)' in s
assert 'IsPaneListCell(v)' in a and 'InExperiment(collection.delegate)' in c
assert 'numberOfLines=3' not in c and 'CGSizeMake(20,20)' in c
assert 'preferredLayoutAttributesFittingAttributes:' in a
assert 'CellStyleKey,nil' in c and 'hadStyle && !IsPaneListCell(v)' in a
assert '确认删除所选项目' in a and '无法恢复' in a
assert 'startAccessingSecurityScopedResource' in s and 'stopAccessingSecurityScopedResource' in q
assert 'NSFileCoordinatorReadingWithoutChanges' in q
for forbidden in ('valueForKey:', 'object_getIvar', 'ivar_getOffset', 'CGAffineTransform', 'removeItemAtURL:', 'moveItemAtURL:', 'copyItemAtURL:', 'UIPasteboard'):
    assert forbidden not in s+a+q,forbidden
print('PASS: scoped native cells and preview relayout, retained native delete confirmation, coordinated QuickLook')
print('LIMIT: cross-pane safety and bookmarks are checked separately by check_070 and production host fixtures')
