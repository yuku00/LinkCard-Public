import json, sys, hashlib, os
from pathlib import Path
from github_native import api, REPO, ROOT
P='/repos/'+REPO
BRANCH='wechat-unified/initial-20261101'
STATE=ROOT/'artifacts'/'release-state.json'
def upload():
    repo=api('GET',P)
    assert repo['full_name']==REPO and not repo['private'] and repo['permissions']['push']
    if STATE.exists():
        state=json.loads(STATE.read_text()); parent=api('GET',P+'/git/ref/heads/'+BRANCH)['object']['sha']
        assert parent==state['commit'], 'Remote changed; refusing to overwrite'
    else:
        parent=api('GET',P+'/git/ref/heads/'+repo['default_branch'])['object']['sha']
        api('POST',P+'/git/refs',{'ref':'refs/heads/'+BRANCH,'sha':parent})
        STATE.write_text(json.dumps({'repo':REPO,'branch':BRANCH,'commit':parent},indent=2))
    commit=api('GET',P+'/git/commits/'+parent)
    allowed=['Sources/Repository.h','Sources/Repository.m','Sources/RepositoryLogic.h','Sources/RepositoryLogic.m','tests/repository_logic.m','Sources/Voice.m','Sources/VoiceLogic.h','Sources/VoiceLogic.m','Sources/VoiceAudio.h','Sources/VoiceAudio.m','tests/voice_logic.m','Sources/AdsLogic.h','Sources/AdsLogic.m','tests/ads_logic.m','tests/ads_hooks.m','tests/ads-stubs/UIKit/UIKit.h','Sources/Moments.m','Sources/MomentsLogic.h','Sources/MomentsLogic.m','tests/moments_logic.m','Sources/HomeLogic.h','Sources/HomeLogic.m','Sources/HomeGroups.m','tests/home_logic.m','Sources/GroupLogic.h','Sources/GroupLogic.m','Sources/Groups.m','tests/group_logic.m','Sources/WU.h','Sources/Core.m','Sources/Ads.m','Sources/Timeline.m','Sources/Appearance.m','Sources/Links.m','Sources/Settings.m','Sources/Messages.m','Sources/MessageLogic.h','Sources/MessageLogic.m','Sources/WUStats.h','Sources/WUStats.m','Sources/ThemeArchive.h','Sources/ThemeArchive.m','Sources/Themes.m','Sources/SunMoon.m','Sources/Surfaces.m','tests/theme_archive.m','tools/build.sh','tools/test_stats.sh','tests/message_logic.m','tests/WUStatsTests.m','tests/test_source.py','README.md','STATUS.md']
    allowed += ['Sources/WUDictation.h','Sources/WUDictation.m','Sources/WUDictationLogic.h','tests/dictation_logic.c','tests/dictation_native.m','tests/dictation-stubs/UIKit/UIKit.h','tests/test_dictation_native.py','DICTATION-INTEGRATION.md']
    allowed += ['Sources/WUStatsVisits.m','Sources/WUStatsOverview.m']
    allowed += ['Sources/Drafts.m','Sources/DraftsLogic.h','Sources/DraftsLogic.m','tests/drafts_logic.m','Sources/DraftMediaLogic.h','Sources/DraftMediaLogic.m','tests/draft_media_logic.m','BUILD-RESULT.md']
    allowed += ['Sources/EmoticonLogic.h','Sources/EmoticonLogic.m','tests/emoticon_logic.m']
    allowed += ['Sources/MomentsCache.m','Sources/MomentsCacheLogic.h','Sources/MomentsCacheLogic.m','tests/moments_cache_logic.m']
    allowed += ['Sources/VoiceSendLogic.h','Sources/VoiceSendLogic.m','tests/voice_send_logic.m']
    allowed += ['Sources/VoicePackLogic.h','Sources/VoicePackLogic.m','Sources/VoicePacks.h','Sources/VoicePacks.m','tests/voice_pack_logic.m']
    allowed += ['tests/test_p0.py','tests/p0_config.m','tests/p0_message.m','tests/message_construction.m','Sources/MessageConstruction.h','Sources/MessageConstruction.m']
    allowed += ['Sources/InteractionLogic.h','Sources/InteractionLogic.m','tests/interaction_logic.m']
    allowed += ['Sources/PluginHub.h','Sources/PluginHub.m','Sources/PluginHubLogic.h','Sources/PluginHubLogic.m','tests/plugin_hub_logic.m']
    allowed += ['Sources/ThemeCatalog.h','Sources/ThemeCatalog.m','Sources/ThemeColors.m','Sources/ThemePrimitives.h','Sources/ThemeLibrary.h','Sources/ThemeLibrary.m','Sources/ThemeRendering.h','Sources/ThemeRendering.m','Sources/SurfaceStyle.m','Sources/SurfaceSettings.m','tests/theme_primitives.c','tests/theme_catalog.m','tests/surface_style_ios.m','tests/run_ui_tests.sh','tests/make_theme_fixtures.py','tests/fixtures/themes/README.md']
    allowed += ['Sources/WUStatsDetails.m','Sources/DraftVideoRestore.m','Sources/LocalVideoContainer.h','Sources/MomentsCacheComments.h','tests/WUStatsCompletionTests.m','tests/voice_pack_files.m','tests/moments_data_completion.m','tests/draft_video_restore.m','tests/local_video_container.c','tools/test_data_completion.sh']
    allowed += ['Sources/WUHostRead.h','Sources/WUHostRead.m','Sources/MomentsHostComments.m','Sources/WUStatsHostProfile.h','Sources/WUStatsHostProfile.m','tests/host_data.m','tools/test_host_data.sh']
    allowed += ['tools/ui-harness/generate.py','tools/ui-harness/run.py','tools/ui-harness/self_check.py','tools/ui-harness/Host.m','tools/ui-harness/SurfaceHarness.xcscheme.in']
    allowed += ['Sources/WUNative.h','Sources/WUNativeLogic.h','Sources/WUNative.m','Sources/WUNativeAction.h','Sources/WUNativeAction.m','Sources/WUNativeInteractions.m','Sources/WUNativeGameLogic.m','Sources/WUNativeGames.m','Sources/WUNativeSettings.m','Sources/WUNativeBoot.h','Sources/WUNativeBoot.c','Sources/WUNativeRecovery.m']
    allowed += ['tests/native/native_policy.c','tests/native/native_boot.c','tests/native/native_hooks.m','tests/native/native_games.m','tests/native/native_interactions_games.m','tests/native/native_guard.m','tests/native/TestHost.h','tests/native/TestHost.m','tests/native/UIKitMock.m','tests/native/stubs/UIKit/UIKit.h','tests/native/clock.h','tests/native/extract_core.py','tests/native/run.sh']
    allowed += ['tools/github_native.py','tools/download.py','tools/verify_build.py','tests/test_github_transport.py']
    allowed += ['Sources/LinkLogic.h', 'Sources/LinkLogic.m', 'Sources/MessageEntries.h', 'Sources/MessageEntries.m', 'Sources/MessageEntryBindings.inc', 'Sources/RepeatOptions.h', 'Sources/RepeatSettings.m', 'tests/message_entry_logic.m', 'tests/test_message_entries.py', 'tools/test_message_entries.sh']
    allowed += ['Sources/WUImageEntry.h','Sources/WUImageEntry.m','tests/image-entry-stubs/UIKit/UIKit.h','tests/image_entry_native.m','tests/test_image_entry_native.py','tests/test_image_entry_contract.py']
    allowed += ['Sources/WUNativeEntries.m','tests/native-gaps/native_entries.m','tests/native-gaps/native_boundary.m','tests/native-gaps/run.sh']
    # Exact manifest closure only: no SDK repository/history, binaries or private media.
    vendor=json.loads((ROOT/'Vendor/manifest.json').read_text())
    for name,digest in vendor['sha256'].items():
        assert name.startswith(('silk/','amr/')) and '..' not in name and Path(name).suffix in ('.c','.cpp','.h')
        assert hashlib.sha256((ROOT/'Vendor'/name).read_bytes()).hexdigest()==digest
    allowed += ['Sources/OfflineVoice.h','Sources/OfflineVoice.c','tools/build_codecs.py','tools/release.py','tests/offline_voice.c','Vendor/manifest.json','Vendor/README.md','Vendor/silk/LICENSE','Vendor/amr/LICENSE','Vendor/amr/NOTICE','tests/fixtures/README.md','tests/fixtures/standard.silk.hex','tests/fixtures/tencent.silk.hex','tests/fixtures/synthetic.amr.hex']
    allowed += ['Vendor/'+name for name in sorted(vendor['sha256'])]
    entries=[{'path':'wechat-unified/'+n,'mode':'100644','type':'blob','content':(ROOT/n).read_text()} for n in allowed]
    entries.append({'path':'.github/workflows/wechat-unified.yml','mode':'100644','type':'blob','content':(ROOT/'workflow/wechat-unified.yml').read_text()})
    # Compare every allowed blob; publish only actual deltas, never dumps or credentials.
    remote=api('GET',P+'/git/trees/'+commit['tree']['sha']+'?recursive=1')
    assert not remote.get('truncated'), 'Cannot audit a truncated remote tree'
    existing={e['path']:e['sha'] for e in remote['tree'] if e['type']=='blob'}
    changed=[]
    for entry in entries:
        data=entry['content'].encode()
        local=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        if existing.get(entry['path'])!=local:
            blob=api('POST',P+'/git/blobs',{'content':entry.pop('content'),'encoding':'utf-8'})
            assert blob['sha']==local
            changed.append(dict(entry,sha=local))
    if not changed:
        print('No actual changes; no commit or CI triggered.'); return
    tree=api('POST',P+'/git/trees',{'base_tree':commit['tree']['sha'],'tree':changed})
    new=api('POST',P+'/git/commits',{'message':os.environ.get('WU_RELEASE_MESSAGE','WeChat Unified: fail-closed production regression fixes'),'tree':tree['sha'],'parents':[parent]})
    assert api('GET',P+'/git/ref/heads/'+BRANCH)['object']['sha']==parent, 'Remote changed during upload'
    api('PATCH',P+'/git/refs/heads/'+BRANCH,{'sha':new['sha'],'force':False})
    state={'repo':REPO,'branch':BRANCH,'commit':new['sha'],'paths':[e['path'] for e in entries]}
    STATE.write_text(json.dumps(state,indent=2)); print(json.dumps(state,indent=2))
def poll():
    state=json.loads(STATE.read_text())
    runs=api('GET',P+'/actions/runs?branch='+BRANCH+'&per_page=10')['workflow_runs']
    runs=[r for r in runs if r['head_sha']==state['commit'] and r['name']=='WeChat Unified dylib']
    data=[{k:r[k] for k in ['id','html_url','status','conclusion','head_sha']} for r in runs]
    (ROOT/'artifacts'/'runs.json').write_text(json.dumps(data,indent=2)); print(json.dumps(data,indent=2))
    if runs:
        jobs=api('GET',P+'/actions/runs/'+str(runs[0]['id'])+'/jobs')['jobs']
        print(json.dumps([{'id':j['id'],'name':j['name'],'conclusion':j['conclusion'],'steps':j['steps']} for j in jobs],indent=2))
if __name__=='__main__': {'upload':upload,'poll':poll}[sys.argv[1]]()
