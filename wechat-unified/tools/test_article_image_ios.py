#!/usr/bin/env python3
"""Reuse existing unsigned UIKit harness; never install a simulator or SDK."""
from pathlib import Path
import importlib.util, json, platform, re, subprocess, sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/ui-harness'))
import generate as harness
from run import choose_device, capture

EXPECTED={'testNativeGestureGateNoAutomaticRequest','testOriginalMenuAndButtonsRemainIdentical',
          'testIndependentButtonExpiresWithoutReplacingHost','testLateDOMReplyCannotReplaceNewSelection',
          'testNavigationScrollAccountAndGenerationInvalidation','testOwnEditorDoesNotRequireChatAndDoesNotPopOtherPage',
          'testUnrelatedPresentationIsNotDismissed','testLayoutOnlyAttachesForArticleAndNeverEvaluatesDOM'}

def generate(out):
    harness.PRODUCTION=('WUImageEntry.m','WUArticleImageFetch.m','EmoticonLogic.m','GroupLogic.m','HomeLogic.m')
    harness.HEADERS=('WU.h','WUArticleImage.h','WUArticleImageFetch.h','WUImageEntry.h')
    project=harness.generate(ROOT,out)
    file=project/'project.pbxproj'; text=file.read_text()
    assert text.count('tests/surface_style_ios.m')==1
    text=text.replace('tests/surface_style_ios.m','tests/article_image_ui.m')
    text=text.replace('-framework XCTest','-framework XCTest -framework WebKit -framework ImageIO -lz')
    file.write_text(text)
    return project

def records(tree):
    out=[]
    def walk(n):
        if isinstance(n,dict):
            if 'testStatus' in n:
                name=n.get('identifier',{}).get('_value','').rsplit('/',1)[-1].removesuffix('()')
                out.append((name,n['testStatus']['_value']))
            for v in n.values(): walk(v)
        elif isinstance(n,list):
            for v in n: walk(v)
    walk(tree); return out

def main():
    if len(sys.argv)==3 and sys.argv[1]=='--generate-only':
        print(generate(Path(sys.argv[2]).resolve())); return
    if platform.system()!='Darwin': raise SystemExit('NOT RUN: real UIKit XCTest requires macOS, Xcode and an already installed iPhone simulator')
    if len(sys.argv)!=2: raise SystemExit('usage: test_article_image_ios.py NEW_RESULT_DIRECTORY')
    out=Path(sys.argv[1]).resolve(); out.mkdir(parents=True,exist_ok=False)
    runtimes=json.loads(capture(['xcrun','simctl','list','runtimes','--json']))
    devices=json.loads(capture(['xcrun','simctl','list','devices','--json']))
    runtime,device=choose_device(runtimes,devices)
    (out/'destination.json').write_text(json.dumps({'runtime':runtime,'device':device},indent=2))
    project=generate(out/'project')
    (ROOT/'build').mkdir(exist_ok=True)
    helper=ROOT/'build/article_ui_matches.inc'
    core=(ROOT/'Sources/Core.m').read_text()
    helper.write_text('#include <string.h>\n'+core[core.index('static const char *Unqualified'):core.index('BOOL WUHook(')])
    booted=device['state']!='Booted'
    try:
        if booted: capture(['xcrun','simctl','boot',device['udid']])
        capture(['xcrun','simctl','bootstatus',device['udid'],'-b'],timeout=240)
        bundle=out/'ArticleTests.xcresult'
        args=['xcodebuild','test','-project',str(project),'-scheme','SurfaceHarness','-sdk','iphonesimulator',
              '-destination',f"platform=iOS Simulator,id={device['udid']}",'-derivedDataPath',str(out/'DerivedData'),
              '-resultBundlePath',str(bundle),'-parallel-testing-enabled','NO','-only-testing:WUSurfaceTests/WUArticleImageTests',
              'CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO']
        log=out/'xcodebuild.log'
        try:
            with log.open('wb') as stream:
                subprocess.run(args,stdout=stream,stderr=subprocess.STDOUT,check=True,timeout=1200)
        finally:
            if log.exists(): print('\n'.join(log.read_text(errors='replace').splitlines()[-60:]),flush=True)
        command=['xcrun','xcresulttool','get','object','--legacy','--path',str(bundle),'--format','json']
        tree=json.loads(capture(command,out/'result-root.json'))
        results=[]
        for i,action in enumerate(tree.get('actions',{}).get('_values',[])):
            ref=action.get('actionResult',{}).get('testsRef',{}).get('id',{}).get('_value')
            if ref: results+=records(json.loads(capture(command+['--id',ref],out/f'tests-{i}.json')))
        if len(results)!=len(EXPECTED) or {n for n,s in results}!=EXPECTED or any(s!='Success' for n,s in results):
            raise RuntimeError(f'Expected every article method exactly once, no skips: {results}')
        (out/'verified-tests.json').write_text(json.dumps(results,indent=2))
        print(f'PASS: {len(EXPECTED)} real UIKit tests with synthetic gestures/WebKit replies. NOT WeChat/device acceptance.')
    finally:
        helper.unlink(missing_ok=True)
        if booted: subprocess.run(['xcrun','simctl','shutdown',device['udid']],check=False,timeout=60)

if __name__=='__main__': main()
