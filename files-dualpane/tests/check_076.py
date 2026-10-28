from pathlib import Path
import subprocess,sys,tempfile
r=Path(__file__).resolve().parents[1]
a=(r/'NativeActions.inc').read_text(); c=(r/'CompactCells.inc').read_text(); n=(r/'NativeCompact.inc').read_text()
assert 'Version: 0.7.10' in (r/'control').read_text()
for bad in ('layoutSubviews','viewDidLayoutSubviews','object_getIvar','ivar_getOffset','valueForKey:', '.frame=', 'CGAffineTransform', 'NSLog('):
    assert bad not in a+c+n,bad
assert 'object_getClass(cell)' in a and 'FPHookDisplay(classes[i])' in a
assert 'class_getSuperclass' in a+n and 'PaneForResponder(cell)' in a and 'InExperiment(collection.delegate)' in a
assert 'accessibilityIsInListMode' in a and 'width*0.75' in a
assert c.index('FPCompactAccessories(cell,compact)') < c.index('if(!publicContent)')
assert c.index('FPCompactBackground(cell,compact)') < c.index('if(!publicContent)')
assert c.index('FPCompactNative(cell,compact)') < c.index('if(!publicContent)')
assert 'FPStyleContentUnsupported' in c
native=n[n.index('static BOOL FPCompactNative'):]
assert native.index('objc_setAssociatedObject(cell,&FPNativeStyleKey,state') < native.index('c.active=YES')
assert 'for(NSUInteger i=0;i<10;i++) if(a[i]!=b[i])' in n
assert 'for(NSUInteger i=10;i<a.count;i++)' in n
assert 'NSLayoutAttributeWidth || edge==NSLayoutAttributeLeft' in n
assert 'for(UIView *owner=row;owner;' in n
assert 'height<targetFont.lineHeight' in n and 'BOOL hasRenaming=' in n
assert 'class_getInstanceMethod(object_getClass(cell),NSSelectorFromString(getter)) && !ABI' in n
with tempfile.TemporaryDirectory() as d:
    output=Path(d)/'style.m'
    subprocess.run([sys.executable,str(r/'tests/style_host.py'),str(output)],check=True)
    host=output.read_text()
    assert n in host and c.replace('#include "NativeCompact.inc"',n) in host
    assert 'return cell.scope' not in host
    for token in ('NativeCases();','PublicCases();','ScopeAndHookCases();','HostBadTitleABI','HostBadDateABI','HostBadRenameABI','NativeFixture','HostDOCControllerChild'):
        assert token in host,token
print('PASS 0.7.9 production expansion, independent gates, real-isa event hooks, ABI fallback, plan-before-setter and no per-frame/offset hooks')
print('LIMIT source contracts; executable Foundation doubles run in CI, not device UIKit')
