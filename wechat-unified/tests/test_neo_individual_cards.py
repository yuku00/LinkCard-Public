"""Source contracts; visual layout and UIKit behaviour still require an iOS device."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class NeoCardsTests(unittest.TestCase):
    def test_independent_opt_in_cards(self):
        helper = (ROOT / 'Sources/WUNeoSettings.h').read_text()
        self.assertIn('initWithFrame:oldTable.frame style:UITableViewStylePlain', helper)
        self.assertIn('cell.backgroundView=WUNeoCardBackground', helper)
        self.assertIn('CGRectInset(container.bounds,16,4)', helper)
        self.assertIn('card.layer.cornerRadius=16', helper)
        self.assertIn('constraintGreaterThanOrEqualToConstant:64', helper)
        self.assertIn('minimum.priority=999', helper)
        self.assertNotIn('UIAppearance', helper.replace('Never use UIAppearance', ''))
        settings = (ROOT / 'Sources/Settings.m').read_text()
        settings = settings.split('@implementation WUSettings', 1)[1].split('@end', 1)[0]
        self.assertIn('WUNeoPrepareTable(self)', settings)
        self.assertIn('return WUNeoCell(cell,nil)', settings)
        self.assertIn('originalPath:', settings)
        self.assertIn('WUSave(key,@(sender.on))', settings)

    def test_settings_long_subtitles_use_self_sizing_constraint_chain(self):
        helper = (ROOT / 'Sources/WUNeoSettings.h').read_text()
        settings = (ROOT / 'Sources/Settings.m').read_text()
        self.assertIn('WUNeoSubtitleContent(cell,&title,&detail,&icon)', settings)
        self.assertIn('sw.accessibilityHint=detail.text', settings)
        for statement in ('text.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor',
                          'text.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor',
                          'text.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor',
                          'title.numberOfLines=0; detail.numberOfLines=0'):
            self.assertIn(statement, helper)

    def test_emoticon_background_is_not_claimed_as_media(self):
        editor = (ROOT / 'Sources/SurfaceSettings.m').read_text()
        self.assertIn('不对表情本体裁圆角', editor)
        self.assertIn('不覆盖表情面板', editor)

if __name__ == '__main__':
    unittest.main()
