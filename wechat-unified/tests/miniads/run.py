#!/usr/bin/env python3
"""System Apple JSC only: compile the production bridge and exact Core hook slice."""
from pathlib import Path
import os, shutil, subprocess, sys
root=Path(__file__).resolve().parents[2]
if not shutil.which('xcrun'):
    print('SKIP: Apple SDK/xcrun unavailable; no Objective-C/JSC execution claimed.')
    sys.exit(1 if os.environ.get('WU_REQUIRE_APPLE_TESTS')=='1' else 77)
build=root/'build/miniads'; build.mkdir(parents=True,exist_ok=True)
core=(root/'Sources/Core.m').read_text()
a=core.index('static const char *Unqualified(')
b=core.index('NSArray *WUHookStatus(',a)
code=core[a:b]
assert 'WUNativeGuardAllowsHooks()' in code and 'WUNativeRecordHook(' in code
(build/'CoreHook.inc').write_text(code)
command=['xcrun','--sdk','macosx','clang','-fobjc-arc','-fobjc-arc-exceptions','-fblocks',
         '-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I',str(root/'tests/ads-stubs'),
         '-I',str(root/'Sources'),'-I',str(build),str(root/'tests/miniads/bridge.m'),
         str(root/'Sources/WUMiniAds.m'),'-framework','Foundation','-framework','JavaScriptCore',
         '-o',str(build/'bridge')]
subprocess.run(command,check=True)
for mode in ('missing','wrong-return','wrong-argument','wrong-count','wrong-self','wrong-command','class-only','inherited','full'):
    subprocess.run([str(build/'bridge'),mode,str(root/'tests/miniads/fixture.js')],check=True,timeout=30)
print('PASS: nine system Apple JavaScriptCore production-bridge processes')
