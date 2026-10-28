from pathlib import Path
import subprocess, sys, tempfile
r=Path(__file__).resolve().parents[1]
n=(r/'NativeCompact.inc').read_text()
wpath=r/'workflow/files-native-probe-roothide.yml'
w=(wpath if wpath.exists() else r.parent/'.github/workflows/files-native-probe-roothide.yml').read_text()
assert 'Version: 0.7.10' in (r/'control').read_text() and 'Version)" = 0.7.10' in w
assert '# Files DualPane 0.7.9' in (r/'README-0.7.9.md').read_text()
for token in ('FPTextWidthPlan', 'NSLayoutRelationLessThanOrEqual', '@"disabled":@YES', 'if(restore && !c.active', 'row.arrangedSubviews.lastObject!=textSlot && !reservation', 'sibling && !tail && c.constant!=0'):
    assert token in n,token
for token in ('FPNativeReadyOnce(cell,identity)', 'FPNativeIdentityMatches(identity,FPNativeIdentity(live))', 'pendingViews', 'FPStyleVisibleCell(live)'):
    assert token in n,token
assert n.count('dispatch_async(')==1
assert n.index('objc_setAssociatedObject(cell,&FPNativeStyleKey,state') < n.index('if(c.active) c.active=NO;', n.index('objc_setAssociatedObject(cell,&FPNativeStyleKey,state'))
for bad in ('layoutSubviews', 'valueForKey:', 'ivar_getOffset', '.frame=', 'CGAffineTransform'):
    assert bad not in n,bad
for token in ('8a803fd6df47febded148e8892a1556071a1a295','width max sibling status delayedready','test "$result" -eq 134','--native-source'):
    assert token in w,token
with tempfile.TemporaryDirectory() as d:
    p=Path(d)/'host.m'; subprocess.run([sys.executable,str(r/'tests/style_host.py'),str(p)],check=True)
    host=p.read_text(); assert n in host
    fixture=(r/'tests/style_width_ready_cases.inc').read_text(); assert fixture in host
    for token in ('WidthLimitCase(NO,NO)', 'WidthLimitCase(YES,NO)', 'WidthLimitCase(NO,YES)', 'WidthLimitCase(YES,YES)', 'SiblingCase();', 'StatusCase();', 'ReadyCase();', 'i<1000', 'readyQueued==queued+1'):
        assert token in fixture,token
print('PASS 0.7.9 production width release/restore, proved provider boundary, same-right and identity-checked one-shot retry contracts')
print('LIMIT executable old-red/new-green equations run in macOS CI; not UIKit device validation')
