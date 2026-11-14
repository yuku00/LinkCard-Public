"""Source guards only: UIKit behavior must still be verified on a device."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class PlusAndSwitchSafety(unittest.TestCase):
    def test_plus_does_not_hook_or_style_unverified_host_view(self):
        source = (ROOT / 'Sources/Surfaces.m').read_text()
        self.assertNotIn('MainFrameActionFloatView', source)
        self.assertNotIn('@"plusSurface"', source)
        self.assertNotIn('plusLayout', source)

    def test_switch_skin_is_visual_only_and_removed_when_disabled(self):
        source = (ROOT / 'Sources/SunMoon.m').read_text()
        self.assertIn('self.userInteractionEnabled=NO', source)
        self.assertNotIn('beginTracking:', source)
        self.assertNotIn('endTracking:', source)
        self.assertNotIn('sendActionsForControlEvents:', source)
        self.assertIn('addTarget:skin action:@selector(sync)', source)
        self.assertIn('removeTarget:skin action:@selector(sync)', source)
        self.assertIn('[skin removeFromSuperview]', source)
        self.assertIn('if(!WUEnabled(@"sunMoon")) { for(UISwitch *sw in switches.allObjects) ClearSwitch(sw);', source)
        self.assertIn('else for(UISwitch *sw in switches.allObjects)', source)

    def test_paused_plus_settings_allow_only_disabling(self):
        settings = (ROOT / 'Sources/Settings.m').read_text()
        surface = (ROOT / 'Sources/SurfaceSettings.m').read_text()
        self.assertIn('@[@"plusSurface",@"首页右上角加号菜单美化（暂不可用）"]', settings)
        self.assertIn('if([key isEqual:@"plusSurface"]) return NO;', settings)
        self.assertIn('sw.enabled=[self available:key] || sw.on', settings)
        self.assertIn('if([key isEqual:@"plusSurface"] && sender.on) { sender.on=NO; return; }', settings)
        self.assertIn('@"plusSurface":@"首页右上加号菜单（暂停）"', surface)
        self.assertIn('if([self.role isEqual:@"plusSurface"]) s.enabled=s.on;', surface)
        self.assertIn('if([self.role isEqual:@"plusSurface"] && s.on) { s.on=NO; return; }', surface)

    def test_legacy_plus_configuration_is_retained(self):
        core = (ROOT / 'Sources/Core.m').read_text()
        roles = (ROOT / 'Sources/ThemeCatalog.m').read_text()
        self.assertIn('@"plusSurface"', core)
        self.assertIn('@"plusSurface"', roles)

if __name__ == '__main__': unittest.main()
