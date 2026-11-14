"""Source contracts only; UIKit interaction still needs an iOS test."""
import re
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / 'Sources/Settings.m').read_text()

class SettingsSearchTests(unittest.TestCase):
    def test_search_uses_display_titles_and_original_paths(self):
        title = SOURCE.split('- (NSString *)titleForOriginalPath:', 1)[1].split('- (void)updateSearchResults', 1)[0]
        search = SOURCE.split('- (void)updateSearchResultsForSearchController:', 1)[1].split('- (NSString *)tableView:', 1)[0]
        cell = SOURCE.split('cellForRowAtIndexPath:', 1)[1].split('- (void)alert:', 1)[0]
        selected = SOURCE.split('didSelectRowAtIndexPath:', 1)[1].split('\n}', 1)[0]
        self.assertIn('self.rows[', title)
        self.assertEqual(len(re.findall(r'@"[^\"]+"', title)), 8)
        self.assertIn('[self titleForOriginalPath:path]', search)
        self.assertIn('localizedCaseInsensitiveContainsString:query', search)
        self.assertIn('self.searchRows=nil', search)
        self.assertIn('p=[self originalPath:p]', cell)
        self.assertEqual(cell.count('[self titleForOriginalPath:p]'), 2)
        self.assertIn('p=[self originalPath:p]', selected)
        self.assertIn('WUShowDiagnostics(self)', selected)
        for forbidden in ('WUValue(', 'WUSave(', 'NSURLSession', 'NSLog', 'NSUserDefaults'):
            self.assertNotIn(forbidden, search)

if __name__ == '__main__':
    unittest.main()
