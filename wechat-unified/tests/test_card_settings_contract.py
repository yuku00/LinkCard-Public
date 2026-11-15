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
    def test_modern_table_and_route_abi(self):
        s=(ROOT/'Sources/WUSettingsListEntry.m').read_text()
        for part in ('m_tableViewMgr','WCTableViewManager','WCTableViewSectionManager',
                     'WCTableViewNormalCellManager','defaultSection','insertSection:At:',
                     'normalCellForSel:target:title:rightValue:canRightValueCopy:',
                     '@encode(NSUInteger)', '@encode(BOOL)'):
            self.assertIn(part, s)
        card=(ROOT/'Sources/WUCardDirect.m').read_text()
        for part in ('WUCardRouteKind(', 'if(routeKind==1)', 'void(*)(id,SEL,id)',
                     'BOOL(*)(id,SEL,id)', 'attempted=YES'):
            self.assertIn(part,card)
        self.assertIn('宿主卡包路由或入口方法缺失', (ROOT/'Sources/Settings.m').read_text())
    def test_settings_fallback_and_dedup(self):
        s=(ROOT/'Sources/WUSettingsListEntry.m').read_text()
        for part in ('NewSettingViewController','MMTableViewInfo','indexOfObjectIdenticalTo:old',
                     'normalCellForSel:target:title:accessoryType:', 'isDescendantOfView:owner.view',
                     'object_getIvar(owner,ivar)!=manager'):
            self.assertIn(part,s)
        self.assertIn('EnsureSettingsEntry(v)',(ROOT/'Sources/Settings.m').read_text())
if __name__ == '__main__': unittest.main()
