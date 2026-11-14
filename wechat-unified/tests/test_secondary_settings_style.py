"""Source contracts only; not a substitute for UIKit compilation/device review."""
from pathlib import Path
import re
import unittest

SOURCES = Path(__file__).resolve().parents[1] / 'Sources'
PAGES = {
    'Groups.m': ['WUGroupsController'], 'Drafts.m': ['WUDraftsList'],
    'WUDiagnostics.m': ['WUDiagnostics'], 'RepeatSettings.m': ['WURepeatSettings'],
    'HomeGroups.m': ['WUHomeGroupsController'], 'VoicePacks.m': ['WUVoicePacksController'],
    'SurfaceSettings.m': ['WUSurfaceEditor', 'WUSurfaceSettings'],
    'EmoticonLibrary.m': ['WUEmoticonLibraryController'], 'WUStats.m': ['WUStatsController'],
    'Themes.m': ['WUThemes'], 'WUNativeSettings.m': ['WUNativeSettings'],
    'MomentsCache.m': ['WUMCacheBrowser'], 'Repository.m': ['WURepositoryController'],
}

class SecondaryStyleTests(unittest.TestCase):
    def test_all_plugin_table_pages_explicitly_opt_in(self):
        found = set()
        for path in SOURCES.glob('*.m'):
            found.update(re.findall(r'@interface\s+(\w+)\s*:\s*UITableViewController', path.read_text()))
        expected = {name for names in PAGES.values() for name in names}
        self.assertEqual(found - {'WUSettings'}, expected)
        for file, names in PAGES.items():
            text = (SOURCES / file).read_text()
            self.assertIn('#import "WUNeoSettings.h"', text)
            for name in names:
                with self.subTest(page=name):
                    block = text.split('@implementation ' + name + '\n', 1)[1].split('\n@end', 1)[0]
                    self.assertEqual(block.count('WUNeoPrepareTable(self);'), 1)
                    cell = block.split('- (UITableViewCell *)tableView:', 1)[1].split('\n- (', 1)[0]
                    self.assertIn('return WUNeoCell(', cell)
                    self.assertNotRegex(cell, r'return (cell|c);')

    def test_scope_and_accessibility(self):
        helper = (SOURCES / 'WUNeoSettings.h').read_text()
        for forbidden in ['[UINavigationBar appearance]', 'method_exchangeImplementations', 'WUHook(', 'navigationController.navigationBar', 'setEnabled:', 'addTarget:', 'WUSave(', 'overrideUserInterfaceStyle=']:
            self.assertNotIn(forbidden, helper)
        for required in ['owner.navigationItem.standardAppearance', 'UIColor.systemGroupedBackgroundColor', 'UIColor.secondarySystemGroupedBackgroundColor', 'scaledFontForFont:', 'adjustsFontForContentSizeCategory=YES', 'UITableViewAutomaticDimension', 'if(symbol.length && !cell.imageView.image)', 'if(!toggle.accessibilityLabel.length)']:
            self.assertIn(required, helper)

    def test_special_content_not_replaced(self):
        themes = (SOURCES / 'Themes.m').read_text()
        self.assertIn('UIContentSizeCategoryIsAccessibilityCategory', themes)
        self.assertIn('scroll.contentLayoutGuide', themes)
        self.assertIn('self.picture.backgroundColor=c', themes)
        diagnostic = (SOURCES / 'WUDiagnostics.m').read_text()
        self.assertIn('preferredFontForTextStyle:UIFontTextStyleFootnote', diagnostic)
        self.assertIn('return WUNeoCell(cell,nil);', diagnostic)
        drafts = (SOURCES / 'Drafts.m').read_text()
        self.assertIn('titleForFooterInSection:', drafts)
        self.assertNotIn('self.tableView.tableFooterView=footer', drafts)

if __name__ == '__main__':
    unittest.main()
