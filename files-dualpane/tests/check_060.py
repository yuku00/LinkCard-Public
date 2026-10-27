from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); e=(r/'Entry.m').read_text(); c=(r/'ColdStart.inc').read_text(); i=(r/'CompactImages.inc').read_text(); b=(r/'BridgeSnapshot.inc').read_text()
assert 'UISegmentedControl' not in s and 'UILayoutConstraintAxisHorizontal' in s
assert 'width>=700' not in s
assert 'FPInstallColdStart();' in e
assert 'FPTryCold' not in e[e.index('viewDidAppear:'):]
for token in ('FPColdConsumed=YES; FPDualPanePresent(root)', 'options.URLContexts.count', 'options.userActivities.count', 'scene:openURLContexts:', 'scene:continueUserActivity:', 'FPReadyTree(root) && FPHasBrowser(root)', 'remaining-1'):
    assert token in c, token
for token in ('performViewAsList:', 'accessibilityIsInListMode', '列表不可用', 'initialListStarted'):
    assert token in s, token
assert 'setDisplayMode:",' not in s
for token in ('DOCThumbnailFittingImageView','NSLayoutAttributeWidth','constraintEqualToConstant:20','FPImageStateKey,nil','setCustomSpacing:6','c.active=NO'):
    assert token in i,token
for token in ('FPBridgeCaptured=YES','indexPathsForSelectedItems','DOCThumbnailFittingImageView','Get(thumb,@"node")','Get(thumb,@"url")','Get(hierarchy,@"lastLocation")','directoryURLGetterInvoked','class_copyMethodList','UIActivityViewController'):
    assert token in b,token
for forbidden in ('NSLog(', 'writeToFile', 'NSURLSession', 'NSFileManager', 'absoluteString', 'object_getIvar', 'ivar_getOffset', 'valueForKey:', 'UTF8String]', 'description]'):
    assert forbidden not in c+i+b,forbidden
assert 'dismissViewControllerAnimated:YES completion:' in b
assert 'methodForSelector' not in b # discovery never invokes arbitrary methods
print('PASS: 0.6 source contracts: once-per-process scene launch, side-by-side, semantic list action, 22pt native icons, opt-in bounded metadata only')
print('LIMIT: UIKit/Files UI, provider getters and launch routing still require device validation; these are source checks, not simulated UI proof')
