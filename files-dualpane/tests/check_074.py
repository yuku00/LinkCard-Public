from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); a=(r/'NativeActions.inc').read_text(); c=(r/'CompactCells.inc').read_text(); n=(r/'NativeLocation.inc').read_text()
assert 'Version: 0.7.5' in (r/'control').read_text()
for bad in ('FPNativeInitialState','dev.filesdualpane.home','HomePolicy','HomeRestore','paneSide','mostRecentlyVisitedLocation'):
    assert bad not in s, bad
assert 'NSUUID.UUID.UUIDString' in s and 'InstallStateIsolation()' in s
assert 'paneStates[OwnState(config)]=[[NSClassFromString(@"DOCUserInterfaceState") alloc] init]' in s
assert '[config copy]' in s and 'identities containsObject:identity' in s
assert 'OwnState(Get(full,@"configuration"))' in n and 'provideContainerControllerAt:' in n
assert s.index('InstallLocationTracking();') < s.index('initWithConfiguration:config sourceObserver:observer')
for file in ('CompactMargins.inc','CompactImages.inc','CompactSelection.inc','CompactDisclosure.inc','CompactSidebar.inc','HomePolicy.inc','HomeNavigation.inc','HomeSave.inc','HomeRestore.inc','layout/DEBIAN/postrm'):
    assert not (r/file).exists(), file
for bad in ('viewDidLayoutSubviews','preferredLayoutAttributesFittingAttributes:', 'CollectLabels','setSelected:', 'NSLayoutConstraint', 'directionalLayoutMargins=zero', '.frame='):
    assert bad not in a+c, bad
assert a.count('visibleCells')==1 and a.index('visibleCells')>a.index('static void FPRestorePaneStyles')
assert 'Files.DOCSidebarViewController' in a and 'collectionView:willDisplayCell:' in a
assert 'margins.leading=10; margins.trailing=10' in c
assert c.index('if(objc_getAssociatedObject(cell,&FPCellBusyKey)) return') < c.index('cell.contentConfiguration=config')
assert 'current!=saved[@"applied"]' in c and 'if(FPCompactConfigurationMatches(current,cell)) return' in c
assert 'UICellAccessoryMultiselect.class' in c and 'UICellAccessoryDisclosureIndicator.class' in c
assert 'removeObjectIdenticalTo:accessory' in c and 'if(saved) return' in c
assert '!cell.isSelected' in c and 'cell.selected=' not in a+c and 'accessibilityTraits=' not in a+c
assert 'scaledFontForFont:' in c and 'compatibleWithTraitCollection:cell.traitCollection' in c
assert 'secondary ? 13 : 14' in c and 'adjustsFontForContentSizeCategory=YES' in c
assert 'updateConfigurationUsingState:' in a and '((void(*)(id,SEL,id))uo)(cell,update,state); FPStyleVisibleCell(cell)' in a
assert c.index('if(objc_getAssociatedObject(cell,&FPCellBusyKey)) return') < c.index('FPCompactAccessories(cell,compact')
for channel in ('FPAccessoriesKey','FPBackgroundKey'):
    assert 'objc_setAssociatedObject(cell,&'+channel+',nil' in c
for token in ('FPPaneMenu(self,0)','FPPaneMenu(self,1)','self.navigationItem.titleView=close'):
    assert token in s
assert 'removePersistentDomain' not in s and 'NSUserDefaults' not in s
print('PASS 0.7.5: no seed/home or private-layout surgery; unique transient states; first-location tracking retained; guarded public styling only; provider accessories/native selection retained; header actions retained')
print('LIMIT source contracts and host doubles do not establish a unique device-hang cause')
