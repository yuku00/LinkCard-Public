import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class Contract(unittest.TestCase):
    def test_card_scope_and_abi(self):
        s=(ROOT/'Sources/WUCardDirect.m').read_text()
        for part in ('WUEnabled(@"cardDirect")','MoreViewController','nav.topViewController!=vc',
                     '@encode(BOOL),@[@"@"]','jumpOrderAndCardCenterFromVc:clickSessionId:',
                     'WUCardShouldFallback','objc_getAssociatedObject(nav,&cardBusy)'):
            self.assertIn(part,s)
        self.assertNotIn('payment',s.lower())
    def test_settings_fallback_and_dedup(self):
        s=(ROOT/'Sources/WUSettingsListEntry.m').read_text()
        for part in ('NewSettingViewController','MMTableViewInfo','indexOfObjectIdenticalTo:old',
                     'normalCellForSel:target:title:accessoryType:', 'isDescendantOfView:owner.view',
                     'object_getIvar(owner,ivar)!=manager'):
            self.assertIn(part,s)
        self.assertIn('EnsureSettingsEntry(v)',(ROOT/'Sources/Settings.m').read_text())
if __name__ == '__main__': unittest.main()
