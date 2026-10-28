from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); a=(r/'NativeActions.inc').read_text(); c=(r/'CompactCells.inc').read_text(); x=(r/'CrossPane.inc').read_text(); f=(r/'FileCore.inc').read_text()
assert 'Version: 0.7.11' in (r/'control').read_text()
assert '左栏 · 操作' not in s and '右栏 · 操作' not in s
assert 'BridgeSnapshot.inc' not in s and 'captureBridge' not in s
assert 'UISegmentedControl' not in s and 'UILayoutConstraintAxisHorizontal' in s
assert 'largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever' in s
assert 'prefersLargeTitles=NO' in s
assert 'numberOfLines=3' not in a+c
assert 'CellStyleKey,nil' in c and 'original.imageProperties' in c
bridge=(r/'DiffableBridge.swift').read_text()
assert 'extension UICollectionViewDiffableDataSource: FPRealDiffableSource' in bridge
assert 'itemIdentifier(for: indexPath)' in bridge and 'dataSource as? FPRealDiffableSource' in bridge
assert 'Mirror(' not in bridge and 'unsafeBitCast' not in bridge
assert 'DiffableBridge.swift' in (r/'Makefile').read_text()
assert 'swiftMapped' in x and 'supportsDataSource:' in x
assert 'indexPathsForSelectedItems' in x and 'itemIdentifierForIndexPath:' in x
assert 'cellForItemAtIndexPath:path' in x and 'DOCThumbnailFittingImageView' in x
assert 'dequeueReusableCell' not in x and 'visible.count==1' in x
assert 'isKindOfClass:UICollectionViewDiffableDataSource.class' in x
n=(r/'NativeLocation.inc').read_text()
assert 'FPNodeURL(Get(location,@"node"))' in n and 'FPLocationInTree(visible)' in n
assert '@"lastLocation"' not in n
assert 'container.panes[index]' in x and 'container.panes[1-index]' in x
assert 'moveItemAtURL:from toURL:to error:&failure' in f
assert 'NSFileCoordinatorWritingForMoving' in f
assert 'fileExistsAtPath:to.path' in f and 'done++' in x
assert 'removeItemAtURL:' not in f+x
for forbidden in ('object_getIvar','ivar_getOffset','valueForKey:', 'UIPasteboard','CGAffineTransform','NSLog('):
    assert forbidden not in s+a+c+x+f,forbidden
assert not (r/'layout/DEBIAN/postrm').exists()
print('PASS 0.7.0 source safety/UI scope, real selection/directory mapping, coordinated transfer, isolated bookmark preferences, no report collection')
print('LIMIT source assertions are not device UI or provider integration tests; host fixture exercises production Foundation core separately')
