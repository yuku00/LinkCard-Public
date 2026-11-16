from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'Sources/HomeGroups.m').read_text()

class HomeProxyAndSelection(unittest.TestCase):
    def test_proxy_requires_both_verified_session_signatures(self):
        self.assertIn('WUVerifiedProxyMethod(manager,WUVerifiedSessionNames) && WUVerifiedProxyMethod(manager,WUVerifiedSessionLookup)', SOURCE)
        self.assertIn('(!verifiedProxy && ![manager isKindOfClass:cls])', SOURCE)

    def test_failed_selection_restores_persisted_tab(self):
        self.assertIn('if(!WUSaveAccountOption(self.account,@"home",s))', SOURCE)
        self.assertIn('sender.selectedSegmentIndex=[self.ids indexOfObject:State(self.account)[@"selected"]]', SOURCE)

if __name__ == '__main__':
    unittest.main()
