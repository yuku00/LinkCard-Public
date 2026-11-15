#!/usr/bin/env python3
"""Reuse existing unsigned UIKit harness; never install a simulator or SDK."""
from pathlib import Path
import importlib.util, json, os, platform, re, subprocess, sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/ui-harness'))
import generate as harness
from run import choose_device, capture

EXPECTED={"testMultipleAndCancel","testSystemAcceptedAndRejected","testSafariDelegateAndNestedPresentation","testResignAndLateSystemReply","testLeavingOwnerAndDismissDelegate","testAccountInvalidationBlocksStaleConfirmation"}

def generate(out):
    harness.PRODUCTION=("MessageEntries.m","LinkLogic.m")
    harness.HEADERS=("WU.h","MessageEntries.h","LinkLogic.h")
    project=harness.generate(ROOT,out)
    file=project/"project.pbxproj"; text=file.read_text()
    assert text.count("tests/surface_style_ios.m")==1
    text=text.replace("tests/surface_style_ios.m","tests/link_flow_ios.m")
    text=text.replace("-framework XCTest","-framework XCTest -framework SafariServices -framework UniformTypeIdentifiers")
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

def failure_context(log):
    lines=log.read_text(errors='replace').splitlines()
    # XCTest may print the exception far before its final failure summary.
    first=next((i for i,line in enumerate(lines) if re.search(
        r"uncaught exception|\*\*\* First throw call stack:|NSException",line,re.I)),None)
    if first is None:
        print('No NSException found in xcodebuild output; showing final 120 lines.',flush=True)
        print('\n'.join(lines[-120:]),flush=True)
    else:
        print(f'First exception context (lines {max(0,first-20)+1}–{min(len(lines),first+101)}):',flush=True)
        print('\n'.join(lines[max(0,first-20):first+101]),flush=True)
        print('Full synthetic-test xcodebuild log is retained in the result directory.',flush=True)

def main():
    if len(sys.argv)==3 and sys.argv[1]=='--generate-only':
        print(generate(Path(sys.argv[2]).resolve())); return
    if platform.system()!='Darwin': raise SystemExit('NOT RUN: real UIKit XCTest requires macOS, Xcode and an already installed iPhone simulator')
    if len(sys.argv)!=2: raise SystemExit('usage: test_link_flow_ios.py NEW_RESULT_DIRECTORY')
    out=Path(sys.argv[1]).resolve(); out.mkdir(parents=True,exist_ok=False)
    runtimes=json.loads(capture(['xcrun','simctl','list','runtimes','--json']))
    devices=json.loads(capture(['xcrun','simctl','list','devices','--json']))
    runtime,device=choose_device(runtimes,devices)
    (out/'destination.json').write_text(json.dumps({'runtime':runtime,'device':device},indent=2))
    project=generate(out/'project')
    booted=device['state']!='Booted'
    try:
        if booted: capture(['xcrun','simctl','boot',device['udid']])
        capture(['xcrun','simctl','bootstatus',device['udid'],'-b'],timeout=240)
        bundle=out/'LinkTests.xcresult'
        args=['xcodebuild','test','-project',str(project),'-scheme','SurfaceHarness','-sdk','iphonesimulator',
              '-destination',f"platform=iOS Simulator,id={device['udid']}",'-derivedDataPath',str(out/'DerivedData'),
              '-resultBundlePath',str(bundle),'-parallel-testing-enabled','NO','-only-testing:WUSurfaceTests/WULinkFlowTests',
              'CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO']
        log=out/'xcodebuild.log'
        # The synthetic harness needs no CI tokens; do not pass them to xcodebuild.
        env={k:os.environ[k] for k in ('PATH','HOME','TMPDIR','USER','LOGNAME','SHELL',
             'DEVELOPER_DIR','SDKROOT','CI','LANG','LC_ALL') if k in os.environ}
        with log.open('wb') as stream:
            subprocess.run(args,stdout=stream,stderr=subprocess.STDOUT,check=True,timeout=1200,env=env)
        command=['xcrun','xcresulttool','get','object','--legacy','--path',str(bundle),'--format','json']
        tree=json.loads(capture(command,out/'result-root.json'))
        results=[]
        for i,action in enumerate(tree.get('actions',{}).get('_values',[])):
            ref=action.get('actionResult',{}).get('testsRef',{}).get('id',{}).get('_value')
            if ref: results+=records(json.loads(capture(command+['--id',ref],out/f'tests-{i}.json')))
        if len(results)!=len(EXPECTED) or {n for n,s in results}!=EXPECTED or any(s!='Success' for n,s in results):
            raise RuntimeError(f'Expected every article method exactly once, no skips: {results}')
        (out/'verified-tests.json').write_text(json.dumps(results,indent=2))
        print(f'PASS: {len(EXPECTED)} real UIKit flow tests with synthetic alert activation/openURL. NOT WeChat/device acceptance.')
    except Exception:
        log=out/'xcodebuild.log'
        if log.exists():
            try: failure_context(log)
            except OSError as error: print(f'Could not read test log: {error}',file=sys.stderr,flush=True)
        raise
    finally:
        if booted:
            try: subprocess.run(['xcrun','simctl','shutdown',device['udid']],check=False,timeout=60)
            except (OSError,subprocess.TimeoutExpired) as error:
                print(f'Simulator shutdown failed: {error}',file=sys.stderr,flush=True)

if __name__=='__main__': main()
