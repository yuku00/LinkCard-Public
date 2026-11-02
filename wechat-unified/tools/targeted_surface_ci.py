"""One-purpose Apple build; explicit uploads, verified TLS, no codec/stats/simulator run."""
import json, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from github_native import api, request_bytes, ROOT, REPO
P='/repos/'+REPO
STATE=ROOT/'artifacts/surface-ci-state.json'
FILES=['Sources/Surfaces.m','Sources/Core.m','Sources/ThemeCatalog.m','Sources/SurfaceSettings.m','Sources/Settings.m','Sources/WU.h','Sources/SurfaceStyle.m','Sources/Groups.m','Sources/WUNative.m','Sources/GroupLogic.m','Sources/GroupLogic.h','Sources/HomeLogic.m','Sources/HomeLogic.h','Sources/ThemeCatalog.h','Sources/ThemePrimitives.h','Sources/ThemeArchive.m','Sources/ThemeArchive.h','Sources/ThemeColors.m','Sources/ThemeLibrary.m','Sources/ThemeLibrary.h','Sources/RepeatOptions.h','Sources/WUArticleImage.h','Sources/WUDictation.h','Sources/InteractionLogic.h','tests/p0_config.m','tests/test_p0.py','tests/theme_catalog.m','tests/test_reply_surface.py','tests/test_quick_reply_surface.py','tests/test_host_popup_surface.py','tests/test_chat_surface.py','evidence/host-popups/WeToast.h','evidence/host-popups/MMToastView.h','evidence/host-popups/MMTipsViewController.h','evidence/host-popups/PROVENANCE.md','tools/release.py','tools/targeted_surface_ci.py']
WORKFLOW='''name: WU surface compile and persistence
on: push
permissions:
  contents: read
jobs:
  surface:
    runs-on: macos-15
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - name: iOS arm64 object compilation
        working-directory: wechat-unified
        run: |
          mkdir -p build/surface-ios
          SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
          for name in Surfaces Core ThemeCatalog SurfaceSettings Settings SurfaceStyle; do
            xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=16.6 -fobjc-arc -fobjc-arc-exceptions -fblocks -c -Wall -Wextra -Werror -Wno-unused-parameter -Wno-nullability-completeness "Sources/$name.m" -o "build/surface-ios/$name.o"
          done
          file build/surface-ios/*.o
      - name: Production configuration save reopen and rejection
        working-directory: wechat-unified
        run: python3 tests/test_p0.py --config-only
      - name: Production theme Foundation tests
        working-directory: wechat-unified
        run: |
          xcrun --sdk macosx clang -fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -ISources tests/theme_catalog.m Sources/ThemeArchive.m Sources/ThemeCatalog.m Sources/ThemeColors.m Sources/ThemeLibrary.m -framework Foundation -lz -o build/surface-theme-tests
          build/surface-theme-tests
      - name: Targeted surface source contracts
        working-directory: wechat-unified
        run: |
          python3 tests/test_reply_surface.py
          python3 tests/test_quick_reply_surface.py
          python3 tests/test_host_popup_surface.py
          python3 tests/test_chat_surface.py
'''
def upload():
    assert not STATE.exists(), 'Existing run state: use poll, do not duplicate workflow'
    base='9da13e7b75539dc440d1e75e97a47552be5d2fb1'
    c=api('GET',P+'/git/commits/'+base)
    entries=[{'path':'wechat-unified/'+n,'mode':'100644','type':'blob','content':(ROOT/n).read_text()} for n in FILES]
    remote=api('GET',P+'/git/trees/'+c['tree']['sha']+'?recursive=1'); assert not remote.get('truncated')
    retired=['Sources/PluginHub.h', 'Sources/PluginHub.m', 'Sources/PluginHubLogic.h', 'Sources/PluginHubLogic.m', 'tests/plugin_hub_logic.m']
    old={i["path"] for i in remote["tree"] if i["type"]=="blob"}
    entries += [{"path":"wechat-unified/"+n,"mode":"100644","type":"blob","sha":None} for n in retired if "wechat-unified/"+n in old]
    disabled='name: Disabled inherited workflow\non: workflow_dispatch\njobs:\n  noop:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo disabled\n'
    for i in remote['tree']:
        if i['path'].startswith('.github/workflows/') and i['type']=='blob':
            entries.append({'path':i['path'],'mode':'100644','type':'blob','content':WORKFLOW if i['path']=='.github/workflows/wu-targeted.yml' else disabled})
    if not any(e['path']=='.github/workflows/wu-targeted.yml' for e in entries):
        entries.append({'path':'.github/workflows/wu-targeted.yml','mode':'100644','type':'blob','content':WORKFLOW})
    t=api('POST',P+'/git/trees',{'base_tree':c['tree']['sha'],'tree':entries})
    n=api('POST',P+'/git/commits',{'message':'Verify latest surface objects and production persistence only','tree':t['sha'],'parents':[base]})
    branch='wechat-unified/surface-persistence-20261102'
    api('POST',P+'/git/refs',{'ref':'refs/heads/'+branch,'sha':n['sha']})
    state={'branch':branch,'commit':n['sha'],'files':FILES}; STATE.write_text(json.dumps(state,indent=2)); print(json.dumps(state,indent=2))
def poll():
    s=json.loads(STATE.read_text())
    runs=api('GET',P+'/actions/runs?branch='+s['branch']+'&per_page=10')['workflow_runs']
    runs=[r for r in runs if r['head_sha']==s['commit'] and r['name']=='WU surface compile and persistence']
    result=[{k:r[k] for k in ('id','html_url','status','conclusion','head_sha')} for r in runs]
    for r in result:
        r['jobs']=api('GET',P+'/actions/runs/'+str(r['id'])+'/jobs')['jobs']
    (ROOT/'artifacts/surface-ci-result.json').write_text(json.dumps(result,indent=2)); print(json.dumps(result,indent=2))
    for r in result:
        if r['status']=='completed':
            dest=ROOT/'artifacts'/('surface-ci-'+str(r['id'])+'-logs.zip')
            dest.write_bytes(request_bytes('GET',P+'/actions/runs/'+str(r['id'])+'/logs'))
            print('Saved logs',dest)
if __name__=='__main__': {'upload':upload,'poll':poll}[sys.argv[1]]()
