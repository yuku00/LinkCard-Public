"""Source-level guard for the voice settings disclosure; UIKit still needs device testing."""
import re
import unittest
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / 'Sources/Settings.m').read_text()

class VoiceDisclosureTests(unittest.TestCase):
    def test_voice_options_are_preserved_and_searchable(self):
        rows = SOURCE.split('self.rows=@[', 1)[1].split(';', 1)[0]
        keys = re.findall(r'@\[@"(voice\w+)"', rows)
        self.assertEqual(keys, ['voiceProgress', 'voiceRealDuration', 'voiceCarry',
                                'voiceCountdown', 'voiceWaveform', 'voiceAlways',
                                'voicePulse', 'voiceSeek'])
        search = SOURCE.split('- (void)updateSearchResultsForSearchController:', 1)[1].split('- (NSString *)tableView:', 1)[0]
        self.assertIn('row<[self originalRowCountForSection:section]', search)
        self.assertIn('section==1 && [@"语音播放"', search)

    def test_disclosure_does_not_save_or_change_settings(self):
        paths = SOURCE.split('- (NSArray<NSIndexPath *> *)visiblePathsForSection:', 1)[1].split('- (NSInteger)tableView:', 1)[0]
        self.assertIn('row==0 || self.voiceOptionsExpanded', paths)
        self.assertIn('indexPathForRow:8 inSection:section', paths)
        select = SOURCE.split('- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:', 1)[1].split('@end', 1)[0]
        branch = select.split('if(p.section==1 && p.row==8)', 1)[1].split('return;', 1)[0]
        self.assertIn('self.voiceOptionsExpanded=!self.voiceOptionsExpanded', branch)
        self.assertNotIn('WUSave', branch)
        self.assertIn('WUSave(key,@(sender.on))', SOURCE)

if __name__ == '__main__':
    unittest.main()
