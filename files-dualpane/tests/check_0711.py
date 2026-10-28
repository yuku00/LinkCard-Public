from pathlib import Path
import json,subprocess,sys,tempfile
r=Path(__file__).resolve().parents[1]
n=(r/'NativeCompact.inc').read_text(); f=json.loads((r/'tests/observed_layout.json').read_text())
assert 'Version: 0.7.11' in (r/'control').read_text()
assert len(f['objects'])==32 and len(f['equations'])==119
cs=f['equations']; assert cs[88][1:8]==[10,7,0,10,8,1,0]
assert cs[29][1:8]==[10,8,0,2,8,1,-16]
assert cs[57][1:8]==[19,5,0,4,6,1,16]
assert not any((c[1] in (3,4,6) and c[2]==7) or (c[4] in (3,4,6) and c[5]==7) for c in cs)
assert abs(f['cellWidth']-39-16-8-45-12-16-f['nativeTextWidth'])<1e-6
assert abs(f['contentWidth']-20-20-6-f['expectedTextWidth'])<1e-6
for token in ('FPInternalGuideEdge','view.safeAreaLayoutGuide','heightProved','@"providerProved"','@"emptyTags"','@"quality"','@"partial"','FPNativeConfiguration','@"spacingStack"'):
 assert token in n,token
for token in ('layoutSubviews','layoutIfNeeded','valueForKey:','ivar_getOffset','setFrame:'):
 assert token not in n,token
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'observed.m'; subprocess.run([sys.executable,str(r/'tests/observed_host.py'),str(p)],check=True)
 s=p.read_text(); assert n in s and 'ObservedCases();' in s
 assert s.count('[cs addObject:c]')==119
print('PASS 0.7.11: full anonymous captured graph, exact width accounting, native source host, no fixed-title hypothesis or layout hooks')
print('LIMIT production-host equations and build are not a post-install real-device result')
