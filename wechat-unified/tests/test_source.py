"""Structural guardrails, not a substitute for iOS runtime tests."""
from pathlib import Path
import re, unittest
ROOT=Path(__file__).resolve().parents[1]
SRC='\n'.join(p.read_text() for p in sorted((ROOT/'Sources').glob('*')))
class Guardrails(unittest.TestCase):
    def test_shared_message_constructor_and_runtime_regressions(self):
        messages=(ROOT/'Sources/Messages.m').read_text()
        voice=(ROOT/'Sources/VoiceSendLogic.m').read_text()
        helper=(ROOT/'Sources/MessageConstruction.m').read_text()
        self.assertIn('WUCreateMessage(NSClassFromString(@"CMessageWrap"),47,account)',messages)
        self.assertIn('WUCreateMessage(cls,34,self.account)',voice)
        self.assertEqual(messages.count('WUMessageCanConstruct('),2)
        self.assertNotIn('WUVoiceConstruct',voice)
        self.assertNotIn('WUMessageConstruct',messages)
        self.assertNotIn('objc_msgSend',helper)
        self.assertNotIn('[NSInvocation ',helper)
        self.assertIn('tests/test_p0.py',(ROOT/'tools/build.sh').read_text())
        self.assertIn('tests/message_construction.m',(ROOT/'tools/build.sh').read_text())
    def test_independent_ad_scope_and_reward_passthrough(self):
        ads=(ROOT/'Sources/Ads.m').read_text()
        hooks=re.findall(r'WUHook\(@"([^"]+)",@"([^"]+)"',ads)
        self.assertEqual(set(hooks), {('BrandTLExptConfig','isExptNotShowAd'),('BrandTLFlutterViewController','enableAd'),('BrandTLCanvasCardMgr','isAdRequestOpen'),('BrandTLCanvasCardMgr','isAdCardOpen'),('BrandTLFlutterViewController','getMagicBrushFlutterPlugins'),('WCAdvertiseDataHelper','IsAdvertiseDataValid:dataItem:'),('WAAppTaskSplashADConfig','canShowSplashADWindow'),('WAAppTaskSplashADConfig','canHotStartShowSplashAD')})
        for forbidden in ['handleJSEvent:', 'isSplashADFinished', 'splashADHasContent', 'WAJSInvoker', 'URLWithString:', 'saveAdvertiseDatas', 'm_advertiseList']:
            self.assertNotIn(forbidden,ads)
        self.assertIn('splashWindowReady && splashHotReady',ads)
        self.assertIn('@"IsAdvertiseDataValid:dataItem:",NO,@encode(BOOL),@[@"@",@"@"]',ads)
        self.assertIn('BOOL original=((BOOL(*)(id,SEL,id,id))momentsValid)',ads)
        for key in ['momentsAds','miniSplashAds']:
            self.assertIn(key,(ROOT/'Sources/Core.m').read_text())
            self.assertIn(key,(ROOT/'Sources/Settings.m').read_text())
        self.assertIn('WUAdsAvailable(key)',(ROOT/'Sources/Settings.m').read_text())
        self.assertIn('tests/ads_logic.m',(ROOT/'tools/build.sh').read_text())
    def test_single_hook_owner(self):
        hooks=re.findall(r'WUHook\(@"([^"]+)",@"([^"]+)",(YES|NO)', SRC)
        self.assertGreaterEqual(len(hooks),10)
        self.assertEqual(len(hooks),len(set(hooks)))
    def test_no_unexpected_delete_or_excluded_client(self):
        for forbidden in ['DelMsg:', 'sendVoice', 'NSURLSession', 'UIKeyboardDockView', 'MSHookMessageEx', 'dlopen(', 'system(', 'OpenRedEnvelopesRequest', 'HBHelperUtil']:
            # Only the evidence-backed host selector is allowed; old helper/AI senders remain forbidden.
            checked=SRC.replace('ResendVoiceMsg:MsgWrap:', '') if forbidden=='sendVoice' else SRC
            self.assertNotIn(forbidden,checked)
        messages=(ROOT/'Sources/Messages.m').read_text()
        self.assertEqual(len(re.findall(r'objc_msgSend\)\([^;]+NSSelectorFromString\(@"AddEmoticonMsg:MsgWrap:"\)', messages)),1)
        self.assertNotIn('SendPatMgr',messages)  # BOOL protocol is deliberately not deferred/replayed.
    def test_runtime_signature_checks_and_local_override(self):
        self.assertIn('method_getNumberOfArguments',SRC)
        self.assertIn('method_copyArgumentType',SRC)
        self.assertIn('method_copyReturnType',SRC)
        self.assertIn('class_addMethod(c,s,replacement',SRC)
    def test_atomic_configuration(self):
        for required in ['O_NOFOLLOW','O_EXCL','fsync(fd)','renameat(', 'backup.json', 'config.json']:
            self.assertIn(required,SRC)
        self.assertNotIn('writeToFile:',SRC)
    def test_defaults_safe(self):
        self.assertIn('@"enabled":@NO',SRC)
        self.assertIn('com.tencent.xin',SRC)
    def test_filters_fail_open(self):
        self.assertIn('if(original || !WUEnabled(@"keywords")',SRC)
        self.assertIn('[text length]>65536',SRC)
        self.assertIn('word.length<=128',SRC)
        self.assertIn('return [out copy]',SRC)
    def test_browser_boundary(self):
        self.assertIn('@[@"http",@"https"]',SRC)
        self.assertIn('c.user.length || c.password.length',SRC)
        self.assertIn('completionHandler:^(BOOL ok)',SRC)
        self.assertNotIn('UIPasteboard',SRC)
    def test_no_embedded_credentials(self):
        self.assertIsNone(re.search(r'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}',SRC))
    def test_theme_local_boundaries(self):
        archive=(ROOT/'Sources/ThemeArchive.m').read_text()
        theme=(ROOT/'Sources/Themes.m').read_text()
        for required in ['inflateInit2(&z,-MAX_WBITS)', 'crc32(', 'NSIntersectionRange', '512', '32*1024*1024', '64*1024*1024', '0170000']:
            self.assertIn(required, archive)
        for required in ['themePack', 'bubblePack', 'RestoreVisibleImages', 'O_NOFOLLOW', 'UIImage', 'UIControlStateNormal', 'NSUUID.UUID.UUIDString', 'NSCache', 'PackPath', 'ValidPNG']:
            self.assertIn(required,theme)
        self.assertNotIn('loadColorFrom',theme)
        self.assertNotIn('replacementResourcePath',theme)
        self.assertNotIn('NSURLSession',theme)
        self.assertIn('tests/theme_archive.m',(ROOT/'tools/build.sh').read_text())
        self.assertTrue((ROOT/'tests/theme_archive.m').is_file())
        # The private publisher is intentionally not shipped to the public runner.
        publisher=ROOT/'tools/release.py'
        if publisher.exists():
            self.assertIn('tests/theme_archive.m',publisher.read_text())
    def test_scoped_sunmoon(self):
        skin=(ROOT/'Sources/SunMoon.m').read_text()
        self.assertEqual(skin.count('sendActionsForControlEvents:UIControlEventValueChanged'),1)
        self.assertNotIn('WUHook(@"UISwitch"',SRC)
        self.assertIn('cancelTrackingWithEvent',skin)
        self.assertIn('sw.on!=on',skin)
        self.assertIn('accessibilityElementsHidden=YES',skin)
        self.assertIn('removeTarget:skin',skin)
    def test_group_lifecycle_and_original_list(self):
        groups=(ROOT/'Sources/Groups.m').read_text()
        for required in ['custom_emoticon_pid','if(!placeholder)', 'return original;', 'setSectionInfo:', 'prepareForReuse', 'p.invalidated=YES', 'p.identifiers=nil', 'UIEdgeInsetsEqualToEdgeInsets', 'gen!=WUContextGeneration()', 'WUMatches(class_getInstanceMethod', 'UIApplicationWillResignActiveNotification']:
            self.assertIn(required, groups)
        self.assertNotIn('setValue:', groups)
        self.assertNotIn('object_setIvar', groups)
        self.assertNotIn('removeObjectAtIndex', groups)
        self.assertIn('tests/group_logic.m',(ROOT/'tools/build.sh').read_text())
    def test_account_manual_toolbar_and_limits(self):
        messages=(ROOT/'Sources/Messages.m').read_text()
        core=(ROOT/'Sources/Core.m').read_text()
        self.assertIn('WUAccountOptions(account)[@"toolbar"]',messages)
        self.assertIn('gen!=generation',messages)
        self.assertIn('StatsReady(Service(@"CMessageMgr"))',messages)
        self.assertIn('if(self.tools) [items removeObject:self.tools]',messages)
        self.assertIn('WUValidAccountOptions',core)
        self.assertIn('data.length>65536',core)
    def test_home_host_snapshot_and_restore(self):
        home=(ROOT/'Sources/HomeGroups.m').read_text()
        for required in ['MMSessionInfo', 'MainSessionMgr', 'CurrentManager()', 'setTotalTopSessionCount:', 'WUHomeProjection', 'self.source[i]', 'self.originalHeaderFrame', 'gen!=WUContextGeneration()', 'self.manager==CurrentManager()', 'self.queued', 'setNormalSessions:']:
            self.assertIn(required,home)
        for forbidden in ['dataSource=', 'object_setIvar', 'setValue:', 'DeleteMsg', 'didSelectRowAtIndexPath:)(']:
            self.assertNotIn(forbidden,home)
        self.assertIn('WURefreshHome(v)',(ROOT/'Sources/Appearance.m').read_text())
        self.assertIn('tests/home_logic.m',(ROOT/'tools/build.sh').read_text())
    def test_stats_only_selected_menu(self):
        messages=(ROOT/'Sources/Messages.m').read_text()
        self.assertNotIn('[items addObject:self.stats]',messages)
        self.assertIn('selected containsObject:@"stats"',messages)
    def test_moments_half_host_containment_and_cancel(self):
        moments=(ROOT/'Sources/Moments.m').read_text()
        for required in ['UIPresentationController', 'UIModalPresentationCustom', 'WUMomentsHeight(CGRectGetHeight(b))', 'shouldRemovePresentersView', 'addChildViewController:self.content', 'didMoveToParentViewController:self', 'WCTimeLineViewController', 'presenter.presentedViewController!=self', 'Current(chat,a,s,g)', '!Responder(chat.view.window,0)', 'closeRestoring:NO', '[self.watch invalidate]']:
            self.assertIn(required,moments)
        self.assertNotIn('UIModalPresentationFullScreen',moments)
        self.assertNotIn('sendPat:',moments)
        self.assertIn('WUCancelMoments();',(ROOT/'Sources/Messages.m').read_text())
    def test_moments_rp_is_object_scoped_and_never_sent(self):
        moments=(ROOT/'Sources/Moments.m').read_text()
        for required in ['MMGrowTextView', 'object:text queue:nil', 'text.markedTextRange!=nil', 'text.isFirstResponder', 'self.consuming', 'text.text=@""', 'budget=500']:
            self.assertIn(required,moments)
        self.assertNotIn('WUHook(',moments)
        self.assertNotIn('text.delegate=',moments)
        self.assertNotIn('AddMsg',moments)
        self.assertIn('tests/moments_logic.m',(ROOT/'tools/build.sh').read_text())
    def test_voice_real_clock_and_bounded_decode(self):
        voice=(ROOT/'Sources/Voice.m').read_text()
        audio=(ROOT/'Sources/VoiceAudio.m').read_text()
        for required in ['currentPlayTime', 'seekToTime:', 'WUVoiceSeekMS', 'WUVoiceLease', 'WUContextGeneration()', 'self.request!=request', 'clockOwner.facade==Facade()', 'self.message', 'didMoveToWindow', 'UIApplicationWillResignActiveNotification']:
            # Completion uses b rather than self inside its weak capture.
            self.assertIn(required.replace('self.request!=request','b.request!=request'),voice)
        self.assertEqual(voice.count('displayLinkWithTarget:'),1)
        self.assertIn('[self.link invalidate]',voice)
        for forbidden in ['setValue:', 'object_setIvar', 'setVoiceTime', 'arc4random', 'becomeFirstResponder', 'sendVoice']:
            self.assertNotIn(forbidden,voice)
        for required in ['ExtAudioFileRead', 'kAudioFormatFlagsNativeFloatPacked', 'O_NOFOLLOW', 'S_ISREG', '8*1024*1024', 'source.mSampleRate*180', 'if(!known) return nil']:
            self.assertIn(required,audio)
        self.assertIn('tests/voice_logic.m',(ROOT/'tools/build.sh').read_text())
    def test_repository_manual_atomic_and_no_receipt_claim(self):
        repo=(ROOT/'Sources/Repository.m').read_text()
        logic=(ROOT/'Sources/RepositoryLogic.m').read_text()
        messages=(ROOT/'Sources/Messages.m').read_text()
        for required in ['self.busy=YES', 'self.submitted', 'if(consumed)', 'work.count>50', 'self.binding.target', '失败：上下文变化，未提交']:
            self.assertIn(required,repo)
        for required in ['NSDataWritingAtomic', 'root[@"account"] isEqual:a', '1024*1024', 'method_getNumberOfArguments(m)!=4', 'submitted=YES; [v invoke]', '已请求（非送达）']:
            self.assertIn(required,logic)
        for required in ['RepositorySource', 'ForwardMessageLogicController', 'ForwardMsg:ToContact:', 'sendMsg:toContactUsrName:', 'gen==generation', 'OpenRepository(owner)', '[Info(wrap) isEqual:identity]', '!WUIsRepositoryController(presented)', 'v.navigationController.topViewController==v']:
            self.assertIn(required,messages)
        self.assertNotIn('350',repo)
        self.assertNotIn('removeItem',repo+logic)
        self.assertIn('tests/repository_logic.m',(ROOT/'tools/build.sh').read_text())
    def test_draft_media_owned_transaction_and_honest_restore(self):
        logic=(ROOT/'Sources/DraftMediaLogic.m').read_text()
        ui=(ROOT/'Sources/Drafts.m').read_text()
        host=(ROOT/'Sources/DraftsLogic.m').read_text()
        for required in ['NSDataWritingAtomic', 'NSDataWritingWithoutOverwriting', 'Hash(check)', 'Load(d,a,e)', '512ULL*1024*1024', 'URLByResolvingSymlinksInPath', 'S_ISREG']:
            self.assertIn(required,logic)
        for forbidden in ['removeItem', 'unlink(', 'NSKeyedArchiver', 'object_setIvar', 'setDraftItemVideoPath']:
            self.assertNotIn(forbidden,logic+ui+host)
        for required in ['UIImagePNGRepresentation', 'imageSelectorController', 'arrImages', 'video-backup', 'WUDraftMediaPut', 'WUDraftMediaURLs', 'isEqualToArray:images', '位置、可见范围', 'draftMediaKey']:
            self.assertIn(required,ui)
        self.assertIn('initWithImages:images contacts:nil',host)
        self.assertIn('tests/draft_media_logic.m',(ROOT/'tools/build.sh').read_text())
    def test_emoticon_original_photos_completion(self):
        logic=(ROOT/'Sources/EmoticonLogic.m').read_text()
        ui=(ROOT/'Sources/Messages.m').read_text().split('// Evidence: WCPulse 0xb8514')[1]
        for required in ['PNGComplete', 'GIFComplete', 'crc32', 'CGImageSourceGetStatusAtIndex', 'self.started', 'self.finished', 'O_NOFOLLOW', '20*1024*1024']:
            self.assertIn(required,logic)
        for required in ['getSelectedMsgs', 'PHAccessLevelAddOnly', 'NSPhotoLibraryAddUsageDescription', 'performChanges:', 'addResourceWithType:PHAssetResourceTypePhoto data:original', 'added && success && !error', 'gen!=generation', 'if(consumed)', 'needUpdateTime:ignoreWxAM:']:
            self.assertIn(required,ui)
        for forbidden in ['UIImagePNGRepresentation', 'UIImageJPEGRepresentation', 'WUHook(', 'sendMsg', 'removeItem', 'UIWebView', 'WKWebView']:
            self.assertNotIn(forbidden,ui+logic)
        self.assertIn('tests/emoticon_logic.m',(ROOT/'tools/build.sh').read_text())
        self.assertIn('count!=GIFComplete(b,n)',logic)
        self.assertIn('本次只请求系统添加照片权限',ui)
        self.assertNotIn('requestAuthorizationForAccessLevel',ui.split('[save startData:')[1])
        self.assertIn('-framework Photos',(ROOT/'tools/build.sh').read_text())
    def test_moments_cache_real_host_safe_local_only(self):
        ui=(ROOT/'Sources/MomentsCache.m').read_text()
        logic=(ROOT/'Sources/MomentsCacheLogic.m').read_text()
        for required in ['getHomepageData', 'onDataUpdated:maxItemID:minItemID:reqFirstPageMd5:', 'Bound(o)', 'WUContextGeneration()', 'UIApplicationStateActive', 'pathForExistData', 'WUMCacheStore', 'WUDraftMediaURLs', 'pending.count>=32', 'isPrivate', 'exceedsVisibleTimeRange', '曾见内容', '评论保存/合并未实现', 'lastErrorAccount isEqual:self.account', 'enabled.boolValue && !Available()', '退出重开联系人朋友圈']:
            self.assertIn(required,ui)
        for forbidden in ['NSTimer', 'setM_cache', 'setValue:', 'deleteDataItem:', 'removeItemAt', 'NSKeyedArchiver', 'NSURLSession']:
            self.assertNotIn(forbidden,ui+logic)
        self.assertIn('WUShowMomentsCache(self)',(ROOT/'Sources/Settings.m').read_text())
        self.assertIn('WUInstallMomentsCache();',(ROOT/'Sources/Core.m').read_text())
        self.assertIn('tests/moments_cache_logic.m',(ROOT/'tools/build.sh').read_text())
        self.assertIn('WURepositorySave',logic)
        self.assertIn('if(!old) return NO',logic)
        self.assertIn('rows.count>=200',logic)
    def test_moments_cache_background_and_owned_reclaim(self):
        ui=(ROOT/'Sources/MomentsCache.m').read_text()
        logic=(ROOT/'Sources/MomentsCacheLogic.m').read_text()
        capture=ui.split('void WUMomentsCacheObserveHost')[1].split('static IMP')[0]
        main=capture.split('dispatch_async(IO()')[0]
        for operation in ['WUDraftMediaReadSource', 'CGImageSourceCreate', 'attributesOfItemAtPath', 'WUMCacheObserve(', 'WUDraftMediaPut']:
            self.assertNotIn(operation,main)
        for marker in ['DISPATCH_QUEUE_SERIAL','NSArray *snapshot=[sources copy]','WUContextGenerationSnapshot','leases[token]','Leased(account)','v.cleaning']:
            self.assertIn(marker,ui)
        for marker in ['OwnedDirectory','st.st_nlink!=1','reclaim.plist','NSSet *leasedIDs','referenced containsObject','NSDataWritingAtomic','st.st_blocks*512','unlink(u.path.fileSystemRepresentation)']:
            self.assertIn(marker,logic)
        self.assertNotIn('unlink(',ui)
        self.assertNotIn('dispatch_sync',logic)
        shared=(ROOT/'Sources/DraftMediaLogic.m').read_text()
        self.assertIn('if(valid && !valid())',shared)
        self.assertNotIn('unlink(',shared)
    def test_voice_forward_selected_once(self):
        messages=(ROOT/'Sources/Messages.m').read_text()
        ui=messages.split('static char voiceForwardKey;')[1]
        logic=(ROOT/'Sources/VoiceSendLogic.m').read_text()
        for word in ['getSelectedMsgs', 'InSession(identity,account,session)', 'WUVoiceSelectedData(wrap)', 'getContactByName:', 'gen!=generation', 'UIApplicationStateActive', 'dispatch_get_global_queue', 'if(confirmed) return', 'operations[identity]', 'pendingAlerts addObject:confirm']:
            self.assertIn(word,ui)
        for word in ['WUOfflineDecode', 'numerator/pcm.rate<=60000', 'methodSignatureForSelector', 'getArgumentTypeAtIndex', 'self.consumed=YES', 'AddLocalMsg:MsgWrap:', 'ResendVoiceMsg:MsgWrap:', 'WURepositoryInvoke', 'if(![insert hasPrefix:@"已请求"] || !current()) return self.status']:
            self.assertIn(word,logic)
        for word in ['ForwardMsg:', 'ResendMsg:', 'writeTo', 'removeItem', 'NSURLSession']:
            self.assertNotIn(word,logic+ui)
        self.assertIn('tests/voice_send_logic.m',(ROOT/'tools/build.sh').read_text())
        self.assertIn('@"voiceForward"',(ROOT/'Sources/GroupLogic.m').read_text())
    def test_voice_pack_owned_pairing_and_leases(self):
        ui=(ROOT/'Sources/VoicePacks.m').read_text()
        logic=(ROOT/'Sources/VoicePackLogic.m').read_text()
        messages=(ROOT/'Sources/Messages.m').read_text()
        for marker in ['DISPATCH_QUEUE_SERIAL', 'UIApplicationWillResignActiveNotification', 'self.navigationController.presentingViewController dismissViewControllerAnimated:NO', 'WUContextGenerationSnapshot()==gen', 'self.cancellation.cancelled', 'WUVoicePackMatches(held,self.binding.version)', 'self.submitted containsObject', 'AVAudioPlayer', 'WUOfflineDecode', 'releaseResource', 'if(consumed) return']:
            self.assertIn(marker,ui)
        for marker in ['WUDraftMediaReadSource', 'NSDataWritingWithoutOverwriting', 'rename(tmp.path.fileSystemRepresentation', 'st.st_nlink!=1', 'current()', '@synchronized(Leases())', 'selected-type34', 'WUVoiceMeasuredMS', '32*1024*1024']:
            self.assertIn(marker,logic)
        for marker in ['OpenVoicePacks(owner)', 'WUVoiceSelectedData(wrap)', 'CFBundleVersion', 'NSDictionary *selectedSnapshot=b.capture()', 'WUIsVoicePacksController(presented)']:
            self.assertIn(marker,messages)
        for forbidden in ['AddLocalMsg:', 'ResendVoiceMsg:', 'NSURLSession', 'AVSpeechSynthesizer']:
            self.assertNotIn(forbidden,ui+logic)
        self.assertIn('tests/voice_pack_logic.m',(ROOT/'tools/build.sh').read_text())
        self.assertIn('-framework AVFoundation',(ROOT/'tools/build.sh').read_text())
    def test_input_and_reversible_card_boundaries(self):
        appearance=(ROOT/'Sources/Appearance.m').read_text()
        surfaces=(ROOT/'Sources/Surfaces.m').read_text()
        messages=(ROOT/'Sources/Messages.m').read_text()
        home=(ROOT/'Sources/HomeGroups.m').read_text()
        for marker in ['WUInputEffect(', 'UIAccessibilityIsReduceMotionEnabled()', 'UITextViewTextDidEndEditingNotification', 'UIApplicationWillResignActiveNotification', 'inputSuspended=YES', 'removeAllAnimations', 'didMoveToWindow', 'isFirstResponder']:
            self.assertIn(marker,appearance)
        for forbidden in ['becomeFirstResponder', 'resignFirstResponder', 'WUHook(@"UIView"', 'WUHook(@"UIButton"']:
            self.assertNotIn(forbidden,appearance+surfaces)
        for marker in ['m_bgImageView','UIImageView.class','isDescendantOfView:cell','WUSurfaceValueOwned','appliedRadius']:
            self.assertIn(marker,surfaces)
        for marker in ['WURestoreMessageSurface(cell)', 'WUCardRole(', 'cellModelOriginal && cellWindowOriginal && cellReuseOriginal']:
            self.assertIn(marker,messages)
        for marker in ['SearchOnlyHeader', 'NewMainFrameViewController', 'WCSearchBar', 'searchHeaderFrame', 'self.table.tableHeaderView==self.searchPlaceholder', 'restoreGroup']:
            self.assertIn(marker,home)
        self.assertNotIn('wcrGrouping_hideSearchHeader',home)
        self.assertIn('tests/interaction_logic.m',(ROOT/'tools/build.sh').read_text())
        for key in ['inputPulse','hideHomeSearch','fileSurface','emoticonSurface']:
            self.assertIn(key,(ROOT/'Sources/Settings.m').read_text())
            self.assertGreaterEqual((ROOT/'Sources/Core.m').read_text().count('@"'+key+'"'),2)
    def test_scope_honest(self):
        status=(ROOT/'STATUS.md').read_text()
        for word in ['未实现','无伪开关','便捷朋友圈','ActionBar','全部 AI','未执行']:
            self.assertIn(word,status)
if __name__=='__main__': unittest.main(verbosity=2)
