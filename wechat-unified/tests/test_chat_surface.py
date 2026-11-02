"""Static integration guards; not a substitute for UIKit or real WeChat tests."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
class ChatSurfaceIntegration(unittest.TestCase):
    def test_configuration_and_ui_wiring(self):
        core=(ROOT/'Sources/Core.m').read_text()
        settings=(ROOT/'Sources/Settings.m').read_text()
        catalog=(ROOT/'Sources/ThemeCatalog.m').read_text()
        editor=(ROOT/'Sources/SurfaceSettings.m').read_text()
        for role in ('chatSendSurface','chatAttachmentSurface'):
            for source in (core,settings,catalog,editor): self.assertIn('@"'+role+'"',source)
        self.assertIn('[v count]>WUSurfaceRoles().count',catalog)
        self.assertIn('WUChatButtonSurfaceAvailable(key)',settings)
    def test_fail_closed_and_reversible_path(self):
        source=(ROOT/'Sources/Surfaces.m').read_text()
        part=source[source.index('// 8.0.55 public headers'):source.index('void WUInstallSurfaces(void)')]
        for required in ('WUMatches(method,@encode(id),@[])','BaseMsgContentViewController',
                         'isDescendantOfView:owner.viewIfLoaded','CheckedObjectGetter(owner,@"toolView")',
                         'CheckedObjectGetter(owner,@"getInputToolView")','CheckedObjectGetter(tool,@"sendButton")',
                         'CheckedObjectGetter(tool,@"attachmentButton")','isKindOfClass:UIButton.class',
                         'isKindOfClass:mmButton','isDescendantOfView:tool','WURestoreConfiguredSurface(button)',
                         'attachment!=send','RestoreChatButtons(tool); ((void(*)(id,SEL))chatToolLayout)',
                         'RestoreChatButtons(tool); ((void(*)(id,SEL))chatToolWindow)'):
            self.assertIn(required,part)
        for forbidden in ('addTarget:', 'removeTarget:', 'setEnabled:', '.enabled='):
            self.assertNotIn(forbidden,part)
        self.assertIn('for(UIView *tool in chatTools.allObjects) { RestoreChatButtons(tool); [tool setNeedsLayout]; }',source)

if __name__ == '__main__': unittest.main()
