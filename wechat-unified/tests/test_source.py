"""Structural guardrails, not a substitute for iOS runtime tests."""
from pathlib import Path
import re, unittest
ROOT=Path(__file__).resolve().parents[1]
SRC='\n'.join(p.read_text() for p in sorted((ROOT/'Sources').glob('*')))
class Guardrails(unittest.TestCase):
    def test_single_hook_owner(self):
        hooks=re.findall(r'WUHook\(@"([^"]+)",@"([^"]+)",(YES|NO)', SRC)
        self.assertGreaterEqual(len(hooks),10)
        self.assertEqual(len(hooks),len(set(hooks)))
    def test_no_unexpected_delete_or_excluded_client(self):
        for forbidden in ['DelMsg:', 'sendVoice', 'NSURLSession', 'UIKeyboardDockView', 'MSHookMessageEx', 'dlopen(', 'system(', 'OpenRedEnvelopesRequest', 'HBHelperUtil']:
            self.assertNotIn(forbidden,SRC)
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
    def test_scope_honest(self):
        status=(ROOT/'STATUS.md').read_text()
        for word in ['未实现','无伪开关','便捷朋友圈','ActionBar','全部 AI','未执行']:
            self.assertIn(word,status)
if __name__=='__main__': unittest.main(verbosity=2)
