"""Structural regression only; actual production parser is exercised by message_entry_logic.m."""
from pathlib import Path
import re, unittest
ROOT = Path(__file__).resolve().parents[1]
def source(name): return (ROOT/'Sources'/name).read_text()
class MessageEntries(unittest.TestCase):
    def test_real_selection_toolbar(self):
        bindings=source('MessageEntryBindings.inc'); messages=source('Messages.m')
        for token in ['getSelectedMsgs','InSession(identity,account,session)','gen!=generation','now[i]!=wraps[i]','Info(wraps[i])','m_nsContent','containsObject:@"messageLinks"']:
            self.assertIn(token,bindings)
        self.assertIn('OpenSelectedLinks(owner)',messages)
        self.assertIn('@"messageLinks"',source('GroupLogic.m'))
        action_arrays=re.findall(r'key=@\[(.*?)\]\[p.row\]',source('Groups.m'))
        self.assertEqual(len(action_arrays),2)
        self.assertEqual(action_arrays[0],action_arrays[1])
        self.assertTrue(all('@"messageLinks"' in actions for actions in action_arrays))
    def test_cancel_does_not_replace_native_context(self):
        messages=source('Messages.m'); ui=source('MessageEntries.m')
        for token in ['WUNativeCancelActions();','WUCancelMessageEntries();','!WUNativeOwnsController(presented)','!WUMessageEntriesOwnsController(presented)']:
            self.assertIn(token,messages)
        for token in ['UIApplicationWillResignActiveNotification','WUChanged','[pending valid]','self.owner.presentedViewController==controller','topViewController==self.owner','self.picked','self.transitioning']:
            self.assertIn(token,ui)
    def test_no_new_sender_or_global_url_hook(self):
        messages=source('Messages.m')
        self.assertIn('WUSubmitEmoticonCopy(',messages)
        production='\n'.join(p.read_text() for p in (ROOT/'Sources').glob('*.m'))
        self.assertEqual(len(re.findall(r'objc_msgSend\)\([^;]+NSSelectorFromString\(@"AddEmoticonMsg:MsgWrap:"\)',production)),1)
        new=''.join(source(n) for n in ['MessageEntries.m','MessageEntryBindings.inc','LinkLogic.m','RepeatSettings.m'])
        for token in ['WUHook(', 'NSURLSession','PHPhotoLibrary','UIImagePNGRepresentation','AddMsg:', 'AddEmoticonMsg:', 'UIPasteboard']:
            self.assertNotIn(token,new)
    def test_file_export_original_and_report(self):
        ui=source('MessageEntries.m')
        for token in ['WUEmoticonRead(path)','WUEmoticonType(data)','initForExportingURLs:@[file] asCopy:YES','documentPickerWasCancelled:','didPickDocumentsAtURLs:','com.compuserve.gif','[data writeToURL:file','self.staging=nil','NSFileCoordinator','O_NOFOLLOW','O_EXCL']:
            self.assertIn(token,ui)
        self.assertIn('系统文件选择器已确认导出',ui)
        self.assertIn('不能确认下载成功',ui)
    def test_reuse_theme_cache_and_defaults(self):
        theme=source('Themes.m'); options=source('RepeatOptions.h')
        function=theme.split('UIImage *WUThemeRepeatIcon',1)[1].split('static IMP namedIMP',1)[0]
        for token in ['Replacement(@"wu_repeat_icon"','[images objectForKey:key]','[images setObject:image','WUThemeRenderFile','SelectionChanged()','stringByResolvingSymlinksInPath']:
            self.assertIn(token,function)
        for token in ['@"imageButton":@YES','@"themeIcon":@YES','@"longDownload":@YES','@"menuRepeat":@NO','@"fileOnly":@NO']:
            self.assertIn(token,options)
        self.assertIn('WUValidRepeatOptions(value)',source('Core.m'))
    def test_explicit_url_choice_and_exact_xml_source(self):
        logic=source('LinkLogic.m'); ui=source('MessageEntries.m')
        for token in ['NSDataDetector','msg/appmsg/url','shouldResolveExternalEntities=NO','<!DOCTYPE','<!ENTITY','targets.count==1','item.name isEqual:@"url"','c.user!=nil']:
            self.assertIn(token,logic)
        for token in ['SFSafariViewController','选择所选消息中的网址','目标域名','不一定是 Safari','WULinkDestination(url)']:
            self.assertIn(token,ui)
        self.assertIn('-framework SafariServices',(ROOT/'tools/build.sh').read_text())
if __name__=='__main__': unittest.main()
