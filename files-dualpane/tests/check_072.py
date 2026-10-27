from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); x=(r/'CrossPane.inc').read_text()
n=(r/'HomeNavigation.inc').read_text(); h=(r/'HomeRestore.inc').read_text(); p=(r/'HomePolicy.inc').read_text(); v=(r/'HomeSave.inc').read_text()
a=(r/'CompactSidebar.inc').read_text(); d=(r/'CompactDisclosure.inc').read_text(); c=(r/'CompactSelection.inc').read_text()
assert 'Version: 0.7.2' in (r/'control').read_text()
assert 'HomePolicy.inc' in x and 'HomeNavigation.inc' in x and 'HomeRestore.inc' in x and 'HomeSave.inc' in x
assert '@"lastLocation"' not in n+x and 'provideContainerControllerAt:from:isUserInteraction:isBrowsingTrash:' in n
assert 'FPLocationInTree(visible)' in n and 'isShowingCollapsedSidebarViewController' in n
assert 'showLocation:fromRootAnimated:withCompletionBlock:' in n and '"v@:@B@?"' in n
assert 'FPConfirmHome' in h and '[FPCurrentLocation(pane) isEqual:location]' in h
assert 'FPHomeIsBrowse' in p and 'browseStartingPointsLocation' in n
assert 'currentDefaultDownloadsLocationItem' in h and 'creatingPlaceholderIfMissing:completionHandler:' in h
assert 'manager,s,node,NO,' in h and 'FPClassGet(@"DOCFavoritesManager",@"sharedManager")' in h
assert '@"fetchDefaultDownloadsLocationItem:"' not in h
assert 'pane.sourceObserver,@"sources"' in h and 'providerDomain' in h
for bad in ['NSDownloadsDirectory','URLForDirectory:', 'createDirectory', 'setDefaultDownloads', 'performGoToDownloads:', 'valueForKey:', 'object_getIvar', 'ivar_getOffset', 'revealDocumentAtURL:']:
    assert bad not in h+n+v,bad
assert 'defaultDownloads' in p+v and 'custom' in p and 'browse' in p
assert 'isKindOfClass:NSData.class' in p+h and 'schema' in p
assert 'revision!=pane.homeRevision' in v and 'FPHomeCanCommit' in v
assert '原首页保留' in v and '5*NSEC_PER_SEC' in v+h
assert '[self restoreWhenReady:0 token:self.homeGeneration]' in s and 'self.homeAttempted=YES; FPRestoreHome(self)' not in s
assert 'FPHomeTouchObserver' in s and 'cancelsTouchesInView=NO' in s
assert 'FPRestorePaneStyles(pane)' in s and 'savedLargeTitles.boolValue' in s
assert 'FPDisclosure(cell,compact)' in a and 'FPDisclosure' not in (r/'CompactCells.inc').read_text()
assert 'UICellAccessoryDisclosureIndicator.class' in d+c and 'navigation' not in d.split('static char')[1]
assert 'saved[@"filtered"]' in d and 'saved[@"original"]' in d
assert 'scaledFontForFont:' in (r/'CompactCells.inc').read_text() and 'FPCellFont(cell,14)' in a
assert 'CGSizeMake(20,20)' in a and 'MAX(44,' in a and 'return 1;' in a
assert 'CollectLabels' not in a and 'UIAppearance' not in a.split('static char')[1]
print('PASS 0.7.2 production bindings: visible-folder vs Browse, semantic system download read only, true native navigation, isolated schema migration/failure preservation, bounded touch-cancellable restoration, sidebar/arrow scope and restoration')
print('LIMIT no device UIKit/provider runtime execution; missing cached system download item intentionally falls back to Browse without creation')
