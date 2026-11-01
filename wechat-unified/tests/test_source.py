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
    def test_scope_honest(self):
        status=(ROOT/'STATUS.md').read_text()
        for word in ['未实现','无伪开关','便捷朋友圈','ActionBar','全部 AI','未执行']:
            self.assertIn(word,status)
if __name__=='__main__': unittest.main(verbosity=2)
