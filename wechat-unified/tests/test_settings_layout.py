"""Source-level regression checks for the grouped settings screen (not UIKit tests)."""
import re
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / 'Sources/Settings.m').read_text()

class SettingsLayoutTests(unittest.TestCase):
    def test_feature_sections_cover_each_existing_key_once(self):
        rows = SOURCE.split('self.rows=@[', 1)[1].split(';', 1)[0]
        keys = re.findall(r'@\[(@"[^"]+"|WUDictation\w+),', rows)
        ranges = re.search(r'NSRange ranges\[\] = \{([^;]+)\};', SOURCE).group(1)
        ranges = [(int(a), int(b)) for a, b in re.findall(r'\{(\d+),(\d+)\}', ranges)]
        self.assertEqual(len(keys), 55)
        self.assertIn('@"emoticonContentCorner"', keys)
        self.assertEqual(len(set(keys)), len(keys))
        self.assertEqual([i for start, count in ranges for i in range(start, start + count)], list(range(len(keys))))
        self.assertEqual([keys[start] for start, _ in ranges], ['@"enabled"', '@"voiceProgress"', '@"ads"', '@"inputBorder"', '@"hideHomeSearch"', '@"convenientMoments"', '@"themes"'])

    def test_recommendation_controls_are_searchable_and_independently_available(self):
        rows = SOURCE.split('self.rows=@[', 1)[1].split(';', 1)[0]
        keys = re.findall(r'@\[(@"[^"]+"|WUDictation\w+),', rows)
        ranges = re.search(r'NSRange ranges\[\] = \{([^;]+)\};', SOURCE).group(1)
        ranges = [(int(a), int(b)) for a, b in re.findall(r'\{(\d+),(\d+)\}', ranges)]
        start, count = ranges[2]
        available = SOURCE.split('- (BOOL)available:', 1)[1].split('NSDictionary *map=', 1)[0]
        search = SOURCE.split('- (void)updateSearchResultsForSearchController:', 1)[1].split('- (NSString *)tableView:', 1)[0]
        self.assertIn('[self titleForOriginalPath:path]', search)
        for key, title in [('officialRecoFlow', '看一看 · 推荐流过滤'), ('officialRecCard', '看一看 · 推荐卡过滤')]:
            self.assertIn(f'@[@"{key}",@"{title}"]', rows)
            self.assertIn(f'@"{key}"', keys[start:start + count])
            self.assertIn(f'@"{key}"', available)
            self.assertIn('return WUAdsAvailable(key)', available)
            detail = SOURCE.split(f'if([key isEqual:@"{key}"]) cell.detailTextLabel.text=', 1)[1].split(';\n', 1)[0]
            for phrase in ('默认关闭', '影响推荐内容', '关闭时透传宿主原行为'):
                self.assertIn(phrase, detail)
        self.assertIn('stringByAppendingString:@" 尚未观察到', SOURCE)

    def test_navigation_uses_opaque_compact_full_screen_presentation(self):
        view = SOURCE.split('@implementation WUSettings', 1)[1].split('- (void)dealloc', 1)[0]
        present = SOURCE.split('void WUShowSettings(', 1)[1].split('@interface WUEntry', 1)[0]
        self.assertIn('self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever', view)
        self.assertIn('self.navigationItem.searchController=search', view)
        for statement in ('UIModalPresentationFullScreen', 'prefersLargeTitles=NO',
                          'translucent=NO', 'configureWithOpaqueBackground',
                          'UIColor.systemBackgroundColor', 'standardAppearance=appearance',
                          'scrollEdgeAppearance=appearance', 'compactAppearance=appearance'):
            self.assertIn(statement, present)
        self.assertLess(present.index('scrollEdgeAppearance=appearance'), present.index('presentViewController:nav'))

    def test_tool_routing_and_native_presentation(self):
        for statement in ['p.row==6) { WUShowRepeatSettings(self)', 'p.row==5) { WUShowNativeSettings(self)', 'p.row==4) { WUShowMomentsCache(self)', 'p.row==3) { WUShowGroups(self)', 'p.row==2) { WUShowThemes(self)', 'p.row==1) { WUShowLinks(self)']:
            self.assertIn(statement, SOURCE)
        for element in ['UITableViewStyleInsetGrouped', 'UITableViewAutomaticDimension', 'adjustsFontForContentSizeCategory=YES', 'systemImageNamed:symbol', 'UIColor.secondarySystemGroupedBackgroundColor']:
            self.assertIn(element, SOURCE)
        self.assertIn('WUSave(key,@(sender.on))', SOURCE)
        self.assertIn('sw.enabled=[self available:key] || sw.on', SOURCE)

    def test_overview_filters_and_keeps_search_global(self):
        overview = SOURCE.split('- (void)buildOverview', 1)[1].split('- (void)dealloc', 1)[0]
        self.assertIn('self.tableView.tableHeaderView=self.overview', overview)
        self.assertIn('[WUValue(@"enabled") boolValue]', overview)
        self.assertIn('已暂停 · 配置保留', overview)
        for section in range(9):
            if section < 7:
                self.assertIn(f'section=={section}', overview)
        self.assertIn('section>=7', overview)
        self.assertIn('if(![self showsSection:s]) return 0', SOURCE)
        search = SOURCE.split('- (void)updateSearchResultsForSearchController:', 1)[1].split('- (NSString *)tableView:', 1)[0]
        self.assertIn('self.categories.selectedSegmentIndex=0', search)
        self.assertIn('systemLayoutSizeFittingSize:', SOURCE)

if __name__ == '__main__':
    unittest.main()
