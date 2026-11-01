"""Native ObjC tests compile the complete production module unchanged against a UIKit mock.
The real iOS UIKit compile remains the build.sh dynamic-library target; no device claim.
"""
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
core=(ROOT/'Sources/Core.m').read_text()
(BUILD/'dictation_core_hooks.inc').write_text(core[core.index('static const char *Unqualified'):core.index('static void Install(void)')])
command=['xcrun','--sdk','macosx','clang','-fobjc-arc','-fobjc-arc-exceptions','-fblocks','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I','tests/dictation-stubs','-I','Sources','-I','build','tests/dictation_native.m','-framework','Foundation','-framework','CoreGraphics','-o',str(BUILD/'dictation-native-tests')]
subprocess.run(command,cwd=ROOT,check=True)
for mode in ('normal','bad-abi','conflict'):
    p=subprocess.run([str(BUILD/'dictation-native-tests'),mode],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    print(p.stdout,flush=True)
    (BUILD/('dictation-native-'+mode+'.txt')).write_text(p.stdout)
    if p.returncode: raise SystemExit(p.returncode)
(BUILD/'dictation_core_hooks.inc').unlink()
(BUILD/'dictation-native-tests').unlink()
