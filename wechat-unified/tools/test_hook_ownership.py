from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
build=root/'build'; build.mkdir(exist_ok=True)
core=(root/'Sources/Core.m').read_text()
fragment=build/'hook_ownership_core.inc'; binary=build/'hook-ownership-tests'
fragment.write_text(core[core.index('static const char *Unqualified'):core.index('NSArray *WUHookStatus')])
try:
    subprocess.run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-fobjc-arc-exceptions','-fblocks','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-I',str(build),str(root/'tests/hook_ownership.m'),'-framework','Foundation','-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
finally:
    fragment.unlink(missing_ok=True); binary.unlink(missing_ok=True)
