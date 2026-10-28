from pathlib import Path
import subprocess,sys,tempfile
r=Path(__file__).resolve().parents[1]
n=(r/'NativeCompact.inc').read_text()
assert 'Version: 0.7.8' in (r/'control').read_text()
with tempfile.TemporaryDirectory() as d:
    p=Path(d)/'host.m'
    subprocess.run([sys.executable,str(r/'tests/style_host.py'),str(p)],check=True); host=p.read_text()
    subprocess.run([sys.executable,str(r/'tests/style_host.py'),str(p),'--mutate-native-trailing'],check=True); mutant=p.read_text()
    assert n in host and host!=mutant
    fixture=(r/'tests/style_trailing_cases.inc').read_text()
    assert fixture in host and fixture in mutant and 'TrailingCases();' in host
    assert 'CGFloat target=i==paths.count-1 ? -10 : 0;' in host
    assert 'CGFloat target=i==paths.count-1 ? -28 : -8;' in mutant
for bad in ('valueForKey:', 'ivar_getOffset', 'layoutSubviews', '.frame=', 'CGAffineTransform'):
    assert bad not in n
assert 'BOOL textEdges=FPPlanTrailing(' in n
assert 'if(!documentAspect && !textEdges) return NO;' in n
print('PASS 0.7.8 production text-edge expansion and non-noop native trailing mutation; runtime equations are checked by macOS fixture')
