"""Apple hostmock runner: complete production module, real Foundation/ImageIO.
No SDK fallback masquerades as a native pass. Run from a merged project.
"""
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'


def main():
    if not shutil.which('xcrun'):
        raise SystemExit('NOT RUN: Apple SDK/xcrun required for image-entry hostmock tests')
    BUILD.mkdir(exist_ok=True)
    core = (ROOT / 'Sources/Core.m').read_text()
    helper = BUILD / 'image_entry_matches.inc'
    helper.write_text(core[core.index('static const char *Unqualified'):core.index('BOOL WUHook(')])
    exe = BUILD / 'image-entry-native-tests'
    command = ['xcrun', '--sdk', 'macosx', 'clang', '-fobjc-arc', '-fobjc-arc-exceptions',
               '-fblocks', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
               '-I', 'tests/image-entry-stubs', '-I', 'Sources', '-I', 'build',
               'tests/image_entry_native.m', 'tests/native/UIKitMock.m',
               'Sources/EmoticonLogic.m', 'Sources/GroupLogic.m', 'Sources/HomeLogic.m',
               '-framework', 'Foundation', '-framework', 'ImageIO', '-framework',
               'CoreGraphics', '-lz', '-o', str(exe)]
    try:
        subprocess.run(command, cwd=ROOT, check=True)
        for mode in ('normal', 'missing', 'wrong-class', 'bad-init', 'bad-setter', 'missing-setter'):
            p = subprocess.run([str(exe), mode], cwd=ROOT, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            print(p.stdout, flush=True)
            (BUILD / ('image-entry-native-' + mode + '.txt')).write_text(p.stdout)
            if p.returncode:
                raise SystemExit(p.returncode)
    finally:
        helper.unlink(missing_ok=True)
        exe.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
