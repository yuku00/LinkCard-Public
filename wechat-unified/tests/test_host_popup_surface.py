"""Source/evidence contracts only: no UIKit or actual WeChat execution."""
from pathlib import Path
import json
import unittest
R=Path(__file__).resolve().parents[1]
class HostPopupSurface(unittest.TestCase):
    def test_configuration_editor_and_availability(self):
        for name in ('Core.m','Settings.m','ThemeCatalog.m','SurfaceSettings.m'):
            self.assertIn('@"hostPopupSurface"',(R/'Sources'/name).read_text())
        self.assertEqual((R/'Sources/Core.m').read_text().count('@"hostPopupSurface"'),2)
        self.assertIn('WUHostPopupSurfaceAvailable()', (R/'Sources/Settings.m').read_text())
        self.assertIn('BOOL WUHostPopupSurfaceAvailable(void);',(R/'Sources/WU.h').read_text())
    def test_evidence_and_fail_closed_scope(self):
        s=(R/'Sources/Surfaces.m').read_text()
        part=s[s.index('// WeToast/MMToastView'):s.index('// The notify view')]
        for token in ('object_getClass(view)!=NSClassFromString(@"MMToastView")',
                      'object_getClass(r)==toastClass', 'isSubclassOfClass:UIViewController.class',
                      'CheckedObjectGetter(owner,@"toastView")!=view',
                      'CheckedFalseGetter(owner,@"blockUserInteraction")',
                      'CheckedFalseGetter(owner,@"loadingStyle")',
                      'topViewControllerInMainWindow', 'presentedViewController',
                      'chatClass && [context isKindOfClass:chatClass]',
                      'object_getClass(context)!=NSClassFromString(@"NewMainFrameViewController")',
                      'CheckedObjectGetter(view,@"backgroundView")',
                      'target==view', 'isDescendantOfView:view', 'CGRectIsEmpty',
                      'WUMatches(class_getInstanceMethod(object_getClass(object),sel),@encode(BOOL),@[])'):
            self.assertIn(token,part)
        for forbidden in ('valueForKey:', 'object_getIvar', 'UIAlertController', 'addTarget:', 'setEnabled:'):
            self.assertNotIn(forbidden,part)
        for cls in ('MMTipsViewController','WeToast','UIAlertController'):
            self.assertNotIn('WUHook(@"'+cls+'"',s)
        # Synthetic public-header summary is a test input, not host/runtime evidence.
        fixture=json.loads((R/'tests/fixtures/host-popup-summary.json').read_text())
        self.assertIn('synthetic', fixture['kind'])
        self.assertEqual(fixture['facts'], {
            'MMToastView.backgroundView': 'UIView',
            'WeToast.toastView': 'MMToastView',
            'MMTipsViewController': ['wcpay_show'],
        })
    def test_fixture_is_packaged_without_raw_headers(self):
        fixture='tests/fixtures/host-popup-summary.json'
        self.assertIn('tests/test_host_popup_surface.py', (R/'tools/build.sh').read_text())
        for script in ('release.py', 'targeted_surface_ci.py'):
            text=(R/'tools'/script).read_text()
            self.assertIn("'"+fixture+"'", text)
            for header in ('MMToastView.h', 'WeToast.h', 'MMTipsViewController.h'):
                self.assertNotIn("'evidence/host-popups/"+header+"'", text)
    def test_lifecycle_and_no_quick_reply_replacement(self):
        s=(R/'Sources/Surfaces.m').read_text()
        self.assertIn('RestoreHostPopup(v); Restore(v); ((void(*)(id,SEL))toastLayout)(v,s)',s)
        self.assertIn('RestoreHostPopup(v); Restore(v); ((void(*)(id,SEL))toastWindow)(v,s)',s)
        self.assertIn('RestoreHostPopup(view); [view setNeedsLayout]',s)
        self.assertIn('if(target) WURestoreConfiguredSurface(target)',s)
        self.assertIn('if(!WUEnabled(@"hostPopupSurface")) return',s)
        self.assertIn('WUStyleSurface(v,@"toastSurface",16); RefreshHostPopup(v)',s)
        self.assertIn('WUApplyConfiguredSurface(target,@"quickReplySurface",16,YES)',s)
if __name__=='__main__': unittest.main()
