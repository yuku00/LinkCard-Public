"""Source/integration contracts only; these do NOT execute UIKit or prove device support."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SRC = (ROOT / 'Sources/WUImageEntry.m').read_text()


class ImageEntryContract(unittest.TestCase):
    def test_checked_source_not_file_import(self):
        self.assertIn('getSelectedMsgs', SRC)
        for part in ('[selected count]==1', '[selected firstObject]==self.wrap',
                     'Identity(self.wrap,self.account,self.session)', '[self.paths isEqual:Paths(self.wrap)]'):
            self.assertIn(part, SRC)
        for forbidden in ('valueForKey:', 'setValue:', 'UIDocumentPicker', 'NSURLSession',
                          'dataWithContentsOfURL:', 'getMsgHdOrMiddleImgData:', 'getPathOfMsgImg:'):
            self.assertNotIn(forbidden, SRC)
        self.assertIn('@[@"m_nsImageHDPath",@"m_nsImagePath"]', SRC)

    def test_context_and_read_limits_reused(self):
        for part in ('WUCurrentAccount()', 'WUContextGeneration()', 'WUChatSession(owner)',
                     'WUEmoticonRead(path)', 'WUEmoticonType(data)', 'path.isAbsolutePath',
                     'path.stringByResolvingSymlinksInPath', 'NSHomeDirectory()', 'errno==ENOENT'):
            self.assertIn(part, SRC)
        self.assertNotIn('writeToFile:', SRC)
        self.assertNotIn('removeItemAtPath:', SRC)

    def test_static_format_not_gif_flattening(self):
        self.assertIn('!memcmp(b+p+4,"acTL",4)', SRC)
        self.assertIn('CGImageSourceGetCount(src)==1', SRC)
        self.assertIn('self.image.images.count', SRC)
        self.assertIn('仅支持完整静态 PNG/JPEG', SRC)
        self.assertIn('GIF、APNG、多帧', SRC)

    def test_native_gate_precedes_allocation_and_once(self):
        body = SRC[SRC.index('- (void)open {'):SRC.index('\n@end\nBOOL WUImageEntryOwnsNavigation')]
        for gate in ('isSubclassOfClass:UIViewController.class', 'class_getInstanceMethod(c,@selector(init))',
                     'class_getInstanceMethod(c,NSSelectorFromString(@"setM_image:"))'):
            self.assertLess(body.index(gate), body.index('[[c alloc] init]'))
        self.assertIn('[editor isKindOfClass:UIViewController.class]', body)
        self.assertEqual(SRC.count('pushViewController:editor animated:YES'), 1)
        self.assertIn('if(!op || op.consumed) return; op.consumed=YES;', SRC)
        self.assertIn('@catch', body)

    def test_no_backend_delegate_or_receipt(self):
        for forbidden in ('startAddEmoticonWithWrap:', 'AddEmoticonMsg:', 'setDelegate:',
                          'EmoticonCustomManageAddLogic', 'upload', '添加成功'):
            self.assertNotIn(forbidden, SRC)
        self.assertIn('当前缓存图片、可能非原图', SRC)
        self.assertIn('打开页面不代表已添加表情', SRC)

    def test_only_owned_controller_removed(self):
        for forbidden in ('popViewControllerAnimated:', 'popToViewController:', 'popToRootViewControllerAnimated:',
                          '[nav dismissViewController', '[self.owner dismissViewController'):
            self.assertNotIn(forbidden, SRC)
        self.assertIn('[stack removeObjectIdenticalTo:editor]', SRC)
        self.assertIn('self.owner.presentedViewController==self.prompt', SRC)
        self.assertIn('[self.timer invalidate]', SRC)
        self.assertIn('UIApplicationWillResignActiveNotification,WUChanged', SRC)
        self.assertIn('self.image=nil; self.wrap=nil;', SRC)

    def test_real_toolbar_wiring(self):
        messages = (ROOT / 'Sources/Messages.m').read_text()
        groups = (ROOT / 'Sources/Groups.m').read_text()
        logic = (ROOT / 'Sources/GroupLogic.m').read_text()
        self.assertIn('#import "WUImageEntry.h"', messages)
        self.assertIn('WUOpenSelectedImageEditor(owner)', messages)
        self.assertIn('WUCancelImageEntries();', messages)
        self.assertIn('!WUImageEntryOwnsNavigation(v)', messages)
        self.assertGreaterEqual(groups.count('@"imageEmoji"'), 2)
        self.assertIn('所选图片 → 微信表情编辑', groups)
        self.assertIn('imageEmoji', logic)
        row_count = re.search(r'self\.identifiers\.count:(\d+)\)', groups)
        self.assertIsNotNone(row_count)
        keys = re.findall(r'@\[(@"search"[^\n]+?)\]\[p\.row\]', groups)
        self.assertEqual(len(keys), 2)
        for key_list in keys:
            self.assertEqual(len(re.findall(r'@"[^"\n]*"', key_list)), int(row_count.group(1)))

    def test_ci_invokes_both_tests(self):
        build = (ROOT / 'tools/build.sh').read_text()
        self.assertIn('python3 tests/test_image_entry_contract.py', build)
        self.assertIn('python3 tests/test_image_entry_native.py', build)
        self.assertIn('Sources/*.m', build)
        self.assertIn('-framework ImageIO', build)


if __name__ == '__main__':
    unittest.main(verbosity=2)
