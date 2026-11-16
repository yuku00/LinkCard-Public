"""Static contracts, not UIKit/device execution."""
from pathlib import Path
import unittest
R = Path(__file__).resolve().parents[1]
M = (R/'Sources/WULinkMenu.inc').read_text()
F = (R/'Sources/MessageEntries.m').read_text()

class ClickContract(unittest.TestCase):
    def test_exact_host_signature(self):
        self.assertIn('WUHook(@"TextMessageCellView",@"onLinkClicked:withRect:",NO,"v"', M)
        self.assertIn('[NSString stringWithUTF8String:@encode(CGRect)]', M)
        self.assertIn('static void WULinkClicked(id cell, SEL cmd, id text, CGRect rect)', M)
    def test_fail_open_to_host(self):
        body=M[M.index('static void WULinkClicked'):M.index('static void WUInstallLinkMenu')]
        self.assertIn('WUOpenClickedLink(owner,clicked,current)) return;',body)
        self.assertEqual(body.count('wuLinkClickOriginal)(cell,cmd,text,rect)'),1)
        for s in ['WULinkSafeURL(text)', 'WUEnabled(@"enhancedLinks")', '[text isKindOfClass:NSString.class]', 'gen==generation', 'Obj(m,@"messageWrap")==w', '[Info(w) isEqual:identity]']:
            self.assertIn(s,body)
    def test_confirm_before_suppressing(self):
        body=F[F.index('BOOL WUOpenClickedLink'):F.index('void WUOpenSelectedLinks')]
        self.assertIn('[flow destination:url]',body)
        self.assertIn('owner.presentedViewController==flow.controller',body)
        self.assertIn('if(!shown) [flow finish];',body)
        self.assertNotIn('openURL:',body)

if __name__ == '__main__': unittest.main(verbosity=2)
