import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / 'Sources/Settings.m').read_text()
SURFACE = (ROOT / 'Sources/SurfaceSettings.m').read_text()
CATALOG = (ROOT / 'Sources/ThemeCatalog.m').read_text()
THEMES = (ROOT / 'Sources/Themes.m').read_text()

class SurfaceSettingsRoutingTests(unittest.TestCase):
    def test_all_roles_are_searchable_without_normal_duplicate_switches(self):
        roles = re.search(r'NSArray \*WUSurfaceRoles\(void\) \{ return @\[(.*?)\];', CATALOG).group(1)
        roles = re.findall(r'@"([^"]+)"', roles)
        rows = re.search(r'self\.rows=@\[(.*?)\];', SETTINGS, re.S).group(1)
        for role in roles:
            self.assertIn('@"' + role + '"', rows, role)
        self.assertIn('if(![self isSurfacePath:p]) [paths addObject:p]', SETTINGS)
        self.assertIn('row<[self originalRowCountForSection:section]', SETTINGS)
        self.assertIn('WUSurfaceTitle(self.rows[', SETTINGS)
        self.assertIn('cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return WUNeoCell(cell,nil)', SETTINGS)

    def test_search_routes_to_same_editor_and_preserves_config(self):
        self.assertIn('WUShowSurfaceEditor(self,self.rows[', SETTINGS)
        self.assertIn('if(![WUSurfaceRoles() containsObject:role] || !owner.navigationController) return', SURFACE)
        self.assertIn('v.role=role; [owner.navigationController pushViewController:v animated:YES]', SURFACE)
        self.assertIn('s.on=[WUValue(self.role) boolValue]', SURFACE)
        self.assertIn('WUSave(self.role,@(s.on))', SURFACE)
        self.assertIn('WUShowSurfaceSettings(self)', THEMES)
        self.assertIn('@"sunMoon"', SETTINGS)
        self.assertIn('@"voiceProgress"', SETTINGS)
        self.assertIn('@"inputPulse"', SETTINGS)

if __name__ == '__main__':
    unittest.main()
