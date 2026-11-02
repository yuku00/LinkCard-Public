"""Source wiring guards only; these do not exercise UIKit or WeChat."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class ReplySurfaceTests(unittest.TestCase):
    def test_role_wired_everywhere(self):
        for name in ('Core.m', 'Settings.m', 'ThemeCatalog.m', 'SurfaceSettings.m'):
            self.assertIn('@"referMessageSurface"', (ROOT/'Sources'/name).read_text())
        core = (ROOT/'Sources/Core.m').read_text()
        self.assertEqual(core.count('@"referMessageSurface"'), 2)

    def test_exact_message_ownership_and_legacy_fallback(self):
        source = (ROOT/'Sources/Surfaces.m').read_text()
        part = source[source.index('static BOOL IsTextMessageReply'):source.index('static void Plus(')]
        for text in ('TextMessageCellView', 'isSubclassOfClass:UIView.class',
                     'v.superview', 'isKindOfClass:cls',
                     'CheckedObjectGetter(parent,@"msgReplyView")==v',
                     'CheckedObjectGetter(parent,@"getMsgReplyView")==v',
                     'RestoreRefer(v); ((void(*)(id,SEL))referLayout)(v,s)',
                     'CheckedObjectGetter(v,@"containerView")',
                     '[container isDescendantOfView:v]',
                     'objc_setAssociatedObject(v,&referTargetKey,target',
                     'WUEnabled(@"referMessageSurface") ? @"referMessageSurface" : @"referSurface"'):
            self.assertIn(text, part)
        self.assertIn('WUMatches(method,@encode(id),@[])', source)
        self.assertIn('RestoreRefer(v); ((void(*)(id,SEL))referWindow)(v,s)', source)
        self.assertIn('if(target && target!=v) Restore(target)', source)
        self.assertIn('[styled addObject:v]', part)

    def test_preview_scoped_and_reversible(self):
        for name in ('Core.m', 'Settings.m', 'ThemeCatalog.m', 'SurfaceSettings.m'):
            self.assertIn('@"textPreviewSurface"', (ROOT/'Sources'/name).read_text())
        source = (ROOT/'Sources/Surfaces.m').read_text()
        part = source[source.index('// Scope the preview toolbar'):]
        for text in ('TextFloatViewController', 'TextMessageCellView', 'MMTextFloatBottomToolView',
                     'CheckedObjectGetter(controller,@"m_delegate")', 'm_bottomToolView',
                     'isKindOfClass:cellClass', 'isKindOfClass:toolbarClass',
                     'isDescendantOfView:controller.viewIfLoaded', 'RestoreTextPreview(controller)',
                     'viewDidDisappear:', 'viewDidLayoutSubviews', 'textPreviewAvailable=YES'):
            self.assertIn(text, part)
        self.assertNotIn('UIAlertController', part)
        self.assertIn('WUTextPreviewSurfaceAvailable()', (ROOT/'Sources/Settings.m').read_text())

if __name__ == '__main__':
    unittest.main()
