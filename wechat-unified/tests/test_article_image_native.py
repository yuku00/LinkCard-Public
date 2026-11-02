"""Apple Foundation/ImageIO hostmock tests. No SDK means NOT RUN, never a pass."""
from pathlib import Path
import shutil, subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'

def main():
    if not shutil.which('xcrun'):
        raise SystemExit('NOT RUN: Apple SDK/xcrun required for article Foundation/ImageIO tests')
    BUILD.mkdir(exist_ok=True)
    common=['xcrun','--sdk','macosx','clang','-fobjc-arc','-fobjc-arc-exceptions','-fblocks',
            '-Wall','-Wextra','-Werror','-Wno-unused-parameter','-ISources']
    fetch=BUILD/'article-fetch-tests'
    helper=BUILD/'image_entry_matches.inc'
    data=BUILD/'article-data-tests'
    core=(ROOT/'Sources/Core.m').read_text()
    helper.write_text(core[core.index('static const char *Unqualified'):core.index('BOOL WUHook(')])
    def run(args,log=None):
        result=subprocess.run(args,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        print(result.stdout,end='',flush=True)
        if log: (BUILD/log).write_text(result.stdout)
        if result.returncode: raise SystemExit(result.returncode)
    try:
        run(common+['tests/article_image_fetch_native.m','-framework','Foundation','-o',str(fetch)])
        run([str(fetch)],'article-fetch-tests.txt')
        run(common+['-Itests/image-entry-stubs','-Ibuild','tests/article_image_data_native.m',
                    'tests/native/UIKitMock.m','Sources/EmoticonLogic.m','Sources/GroupLogic.m','Sources/HomeLogic.m',
                    '-framework','Foundation','-framework','ImageIO','-framework','CoreGraphics','-lz','-o',str(data)])
        for mode in ('normal','missing','wrong-class','bad-init','bad-setter','missing-setter'):
            run([str(data),mode],'article-data-'+mode+'.txt')
    finally:
        for path in (fetch,data,helper): path.unlink(missing_ok=True)

if __name__=='__main__': main()
