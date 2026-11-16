import unittest
from pathlib import Path
R = Path(__file__).resolve().parents[1]
def source(name): return (R/'Sources'/name).read_text()
class SettingsRepair(unittest.TestCase):
    def test_home_search_preference_depends_on_installed_layout_not_observation(self):
        self.assertIn('BOOL WUHomeSearchAvailable(void) { return homeLayout != NULL; }', source('Appearance.m'))
        self.assertIn('if(hide && !self.searchHeader && SearchOnlyHeader(candidate))', source('HomeGroups.m'))
    def test_dictation_preference_depends_on_hooks_not_open_chat(self):
        text=source('WUDictation.m')
        self.assertIn('&& ready;', text[text.index('BOOL WUDictationAvailable'):])
        self.assertIn('Owned(',text)
    def test_background_does_not_restore_separators_without_reapply(self):
        text=source('Appearance.m')
        self.assertIn('if([n.name isEqual:WUChanged]) { RestoreTables();',text)
        self.assertIn('[home.viewIfLoaded setNeedsLayout]',text)
    def test_settings_list_rechecked_on_layout(self):
        text=source('Settings.m')
        text=text[text.index('static void SettingsLayout'):text.index('void WUInstallSettings')]
        self.assertIn('WUEnsureSettingsListRow(v)',text)
    def test_removed_finder_hook_not_data(self):
        self.assertNotIn('@"homeFinder"',source('WUNativeSettings.m'))
        self.assertNotIn('FinderLayout',source('WUNativeEntries.m'))
        self.assertIn('@"homeFinder"',source('WUNative.m'))
if __name__ == '__main__': unittest.main()
