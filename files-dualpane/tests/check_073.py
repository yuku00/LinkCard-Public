from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); x=(r/'CrossPane.inc').read_text()
n=(r/'NativeLocation.inc').read_text(); p=(r/'ProviderLocation.inc').read_text()
c=(r/'CompactCells.inc').read_text(); a=(r/'CompactSidebar.inc').read_text(); m=(r/'CompactMargins.inc').read_text(); i=(r/'CompactImages.inc').read_text()
assert 'Version: 0.7.3' in (r/'control').read_text()
for bad in ['FPRestoreHome','FPDefaultDownloads','restoreWhenReady','homeGeneration','setRestoreLastVisitedLocation:', 'setSaveLastVisitedLocation:', 'NSUUID', '设当前位置为首页','清除首页','showLocation:']:
    assert bad not in s+x+n+p,bad
assert '@"dev.filesdualpane.session.%@.%@",scene,adapter.paneSide' in s
assert 'FPNativeInitialState(Get(original,@"configuration"))' in s
assert 'mostRecentlyVisitedLocation' in s and 'mostRecentEffectiveRootLocation' in s
assert 'interfaceStateForConfiguration:' in s and '[value copy]' in s
assert 'paneStates[OwnState(config)]=FPNativeInitialState' in s
assert s.index('paneStates[OwnState(config)]=FPNativeInitialState') < s.index('initWithConfiguration:config sourceObserver:observer')
assert '@[copy,move]' in x and 'FPTransferOne' in x
assert 'FPLocationInTree(visible)' in n and '@"lastLocation"' not in n
assert 'fetchItemForURL:completionHandler:' in p and 'fetchURLForItem:creatingPlaceholderIfMissing:completionHandler:' in p
assert 'manager,s,node,NO,' in p
assert 'removePersistentDomainForName:@"dev.filesdualpane.home"' in s
for source in (c,a):
    assert 'FPContentMargins(cell,compact)' in source
    assert 'axesPreservingSuperviewLayoutMargins=0' in source
    assert 'axesPreservingSuperviewLayoutMargins=' in source
assert 'preservesSuperviewLayoutMargins=NO' in m and 'directionalLayoutMargins=zero' in m
assert 'FPTextOnlySlot(text)' in i and 'stack.distribution=UIStackViewDistributionFill' in i
assert 'UIStackViewAlignmentFill' in i and 'NSLayoutAttributeWidth' in i
assert 'state[@"text"]' in i and 'state[@"stacks"]' in i
for bad in ['CGAffineTransform','object_getIvar','valueForKey:', 'killall cfprefsd']:
    assert bad not in s+x+n+p+c+a+m+i,bad
print('PASS 0.7.3 no home/download forcing, stable isolated native-state seeds, native flags inherited, scoped real margins/text-stack width reclaimed, provider resolver and transfer retained')
print('LIMIT source contracts plus CI Foundation doubles do not prove Files/UIKit device restoration/rendering')
