#!/usr/bin/env python3
"""Generate/run synthetic-host tests using a real iOS UIKit XCTest simulator."""
from pathlib import Path
import json, platform, subprocess, sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/ui-harness'))
import generate as harness
from run import choose_device, capture
sys.path.insert(0,str(ROOT/'tools'))
from test_article_image_ios import records

def generate(out):
    harness.PRODUCTION=(); harness.HEADERS=()
    project=harness.generate(ROOT,out)
    pbx=project/'project.pbxproj'; text=pbx.read_text()
    assert text.count('tests/surface_style_ios.m')==1
    pbx.write_text(text.replace('tests/surface_style_ios.m','tests/neo_cards_ios.m'))
    return project

def main():
    if len(sys.argv)==3 and sys.argv[1]=='--generate-only':
        print(generate(Path(sys.argv[2]).resolve())); return
    if platform.system()!='Darwin': raise SystemExit('NOT RUN: real UIKit XCTest requires macOS, Xcode and an installed iPhone simulator')
    if len(sys.argv)!=2: raise SystemExit('usage: test_page_geometry_ios.py NEW_RESULT_DIRECTORY')
    out=Path(sys.argv[1]).resolve(); out.mkdir(parents=True,exist_ok=False)
    runtime,device=choose_device(json.loads(capture(['xcrun','simctl','list','runtimes','--json'])),json.loads(capture(['xcrun','simctl','list','devices','--json'])))
    project=generate(out/'project'); booted=device['state']!='Booted'
    try:
        if booted: capture(['xcrun','simctl','boot',device['udid']])
        capture(['xcrun','simctl','bootstatus',device['udid'],'-b'],timeout=240)
        subprocess.run(['xcodebuild','test','-project',str(project),'-scheme','SurfaceHarness','-sdk','iphonesimulator','-destination',f"platform=iOS Simulator,id={device['udid']}",'-derivedDataPath',str(out/'DerivedData'),'-resultBundlePath',str(out/'Tests.xcresult'),'-parallel-testing-enabled','NO','-only-testing:WUSurfaceTests/WUNeoCardTests','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO'],check=True,timeout=1200)
        command=['xcrun','xcresulttool','get','object','--legacy','--path',str(out/'Tests.xcresult'),'--format','json']
        tree=json.loads(capture(command)); results=[]
        for action in tree.get('actions',{}).get('_values',[]):
            ref=action.get('actionResult',{}).get('testsRef',{}).get('id',{}).get('_value')
            if ref: results+=records(json.loads(capture(command+['--id',ref])))
        expected={'testProductionCards','testLongSubtitlesStayInsideAutomaticHeightCards','testSystemSubtitleCardsFitAtAccessibleSizes','testThemePreviewMinimumGrowsForLongNames','testReusedCellReplacesVisibleText'}
        if len(results)!=len(expected) or {n for n,s in results}!=expected or any(s!='Success' for n,s in results):
            raise RuntimeError(f'Expected test without skips: {results}')
        print('PASS: synthetic host with real UIKit; not WeChat/device acceptance')
    finally:
        if booted: subprocess.run(['xcrun','simctl','shutdown',device['udid']],check=False,timeout=60)
if __name__=='__main__': main()
