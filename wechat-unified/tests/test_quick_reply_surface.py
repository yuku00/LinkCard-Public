"""Static contracts only; no UIKit runtime or WeChat coverage."""
import unittest
from pathlib import Path
R=Path(__file__).resolve().parents[1]
class QuickReplySurface(unittest.TestCase):
    def test_config_wiring(self):
        for f in ('Core.m','Settings.m','ThemeCatalog.m','SurfaceSettings.m'):
            self.assertIn('@"quickReplySurface"',(R/'Sources'/f).read_text())
        self.assertEqual((R/'Sources/Core.m').read_text().count('@"quickReplySurface"'),2)
        self.assertIn('WUQuickReplySurfaceAvailable()', (R/'Sources/Settings.m').read_text())
    def test_scope_and_restore(self):
        s=(R/'Sources/Surfaces.m').read_text()
        part=s[s.index('// The notify view'):s.index('void WUInstallSurfaces(void)')]
        for t in ('CheckedObjectGetter(view,@"contentView")','target==view',
                  'isKindOfClass:UIView.class','isDescendantOfView:view','if(!view.window) return',
                  'RestoreQuickReply(view); ((void(*)(id,SEL))quickReplyLayout)',
                  'RestoreQuickReply(view); ((void(*)(id,SEL))quickReplyWindow)',
                  'if(!WUEnabled(@"quickReplySurface")) return', 'WURestoreConfiguredSurface(target)'):
            self.assertIn(t,part)
        self.assertIn('WUMatches(method,@encode(id),@[])',s)
        for sel in ('@"didMoveToWindow"','@"layoutSubviews"'):
            self.assertIn('WUHook(@"QuickReplyMsgNotifyView",'+sel,s)
        self.assertIn('RestoreQuickReply(view); [view setNeedsLayout]',s)
        for forbidden in ('UIAlertController','addTarget:', 'setEnabled:','notifyItem'):
            self.assertNotIn(forbidden,part)
if __name__=='__main__': unittest.main()
