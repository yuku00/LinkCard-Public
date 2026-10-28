from pathlib import Path
import subprocess, sys, tempfile
r=Path(__file__).resolve().parents[1]
n=(r/'NativeCompact.inc').read_text()
c=(r/'CompactCells.inc').read_text()
w=(r/'workflow/files-native-probe-roothide.yml').read_text() if (r/'workflow/files-native-probe-roothide.yml').exists() else (r.parent/'.github/workflows/files-native-probe-roothide.yml').read_text()
assert 'Version: 0.7.8' in (r/'control').read_text()
assert '# Files DualPane 0.7.7' in (r/'README-0.7.7.md').read_text()
assert 'Version)" = 0.7.8' in w
assert 'CGSizeMake(20*MIN(1,ratio),20*MIN(1,1/ratio))' in n
assert 'FPDocumentAspect(image,root)' in n
assert 'c.firstItem!=image || c.secondItem!=image' in n
assert 'FPPlanDocumentDimensions(root,slot,image,documentAspect,constraints)' in n
assert 'FPPlanDocumentDimensions(root,image,image,documentAspect,constraints)' in n
assert 'c.multiplier==1 && c.constant==0 && c.firstAttribute==c.secondAttribute' in n
assert 'if(!c.active || c.constant!=' in n
assert 'secondary ? 13 : 14' in c
assert 'CGFloat inset=10;' in n and 'setCustomSpacing:6 afterView:slot' in n
# Each mutation must actually change expanded production, not just test text.
with tempfile.TemporaryDirectory() as d:
    path=Path(d)/'style.m'
    def generate(*flags):
        subprocess.run([sys.executable,str(r/'tests/style_host.py'),str(path),*flags],check=True)
        return path.read_text()
    host=generate()
    assert n in host
    for name in ('DocumentCases();','AssertDocument','Ratio(', 'nativeReentry=reused.cell', '[reused.cell prepareForReuse]', 'i<1000'):
        assert name in host,name
    for flag in ('--mutate-margin','--mutate-native-size','--mutate-document-square'):
        assert flag in w,flag
        mutant=generate(flag)
        assert mutant!=host,flag
        assert mutant[mutant.index('// Explicit dimension fixtures'):]==host[host.index('// Explicit dimension fixtures'):],flag
print('PASS 0.7.7 aspect-fit source contracts, coupled slots, fallback, reentry/reuse fixtures, non-noop mutations and version alignment')
print('LIMIT executable production host/mutation results require macOS CI; no device layout claim')
