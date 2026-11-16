"""Static checks; UIKit and host lifecycle require device verification."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class SettingsPolishTests(unittest.TestCase):
    def test_entry_reconciles_without_replacing_host_items(self):
        text = (ROOT / 'Sources/Settings.m').read_text()
        helper = text.split('static void EnsureSettingsEntry', 1)[1].split('static void Appeared', 1)[0]
        layout = text.split('static void SettingsLayout', 1)[1].split('void WUInstallSettings', 1)[0]
        self.assertIn('rightBarButtonItems mutableCopy', helper)
        self.assertIn('containsObject:entry.button', helper)
        self.assertIn('if(v.view.window) EnsureSettingsEntry(v)', layout)
        self.assertIn('没有找到相关设置', text)
        self.assertIn('self.tableView.backgroundView=nil', text)

    def test_scoped_separator_and_attachment_default(self):
        helper = (ROOT / 'Sources/WUNeoSettings.h').read_text()
        surfaces = (ROOT / 'Sources/Surfaces.m').read_text()
        self.assertIn('table.separatorStyle=UITableViewCellSeparatorStyleNone', helper)
        self.assertIn('WUApplyConfiguredSurface(attachment,@"chatAttachmentSurface",8,NO)', surfaces)
        style = (ROOT / 'Sources/SurfaceStyle.m').read_text()
        self.assertIn('if(background||s[@"background"]||s[@"backgroundDark"])', style)

if __name__ == '__main__':
    unittest.main()
