from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); a=(r/'NativeActions.inc').read_text(); c=(r/'CompactCells.inc').read_text(); x=(r/'CrossPane.inc').read_text(); f=(r/'FileCore.inc').read_text()
assert 'Version: 0.7.0' in (r/'control').read_text()
assert '左栏 · 操作' not in s and '右栏 · 操作' not in s
assert 'BridgeSnapshot.inc' not in s and 'captureBridge' not in s
assert 'self.mode.selectedSegmentIndex=0' in s
assert 'largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever' in s
assert 'prefersLargeTitles=NO' in s
assert 'numberOfLines=3' not in a+c
assert 'FPNameLines' in c and 'FPCompactRowHeight' in a
assert 'UIFontMetrics' in c and 'clipsToBounds=YES' in c
assert 'CellStyleKey,nil' in c and 'original.textProperties.font' in c
assert 'indexPathsForSelectedItems' in x and 'itemIdentifierForIndexPath:' in x
assert 'cellForItemAtIndexPath' not in x
assert 'isKindOfClass:UICollectionViewDiffableDataSource.class' in x
assert 'lastLocation' in x and 'DOCConcreteLocation' in x
assert 'FPNodeURL(Get(location,@"node"))' in x
assert 'container.panes[index]' in x and 'container.panes[1-index]' in x
assert 'NSURLBookmarkCreationMinimalBookmark' in f and 'NSURLBookmarkResolutionWithoutUI' in f
assert 'stale || !url.isFileURL' in f and 'dev.filesdualpane.home' in x
assert 'importIfNeeded:NO' in x and '未确认恢复成功' in x
assert 'moveItemAtURL:from toURL:to error:&failure' in f
assert 'NSFileCoordinatorWritingForMoving' in f
assert 'fileExistsAtPath:to.path' in f and 'done++' in x
assert 'removeItemAtURL:' not in f+x
for forbidden in ('object_getIvar','ivar_getOffset','valueForKey:', 'UIPasteboard','CGAffineTransform','NSLog('):
    assert forbidden not in s+a+c+x+f,forbidden
post=(r/'layout/DEBIAN/postrm').read_text()
assert 'rm -f "$directory/dev.filesdualpane.home.plist"' in post and 'rm -rf' not in post
print('PASS 0.7.0 source safety/UI scope, real selection/directory mapping, coordinated transfer, isolated bookmark preferences, no report collection')
print('LIMIT source assertions are not device UI or provider integration tests; host fixture exercises production Foundation core separately')
