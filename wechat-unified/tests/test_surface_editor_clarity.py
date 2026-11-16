"""Editor copy/input contracts; not a substitute for an iOS device test."""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'Sources/SurfaceSettings.m').read_text()

class SurfaceEditorClarityTests(unittest.TestCase):
    def test_preview_and_layout_limit_are_honest(self):
        self.assertIn('浅色样式示意', SOURCE)
        self.assertIn('深色样式示意', SOURCE)
        self.assertIn('该项目暂不支持宽高调整', SOURCE)
        self.assertIn('背景宽度比例 (0.7–1.3)', SOURCE)
        self.assertIn('背景高度比例 (0.7–1.3)', SOURCE)

    def test_field_specific_input_guidance(self):
        self.assertIn('例如 HelveticaNeue', SOURCE)
        self.assertIn('#RRGGBB 或 #RRGGBBAA', SOURCE)
        self.assertIn('![key isEqual:@"fontWeight"]', SOURCE)
        self.assertIn('UIKeyboardTypeDecimalPad', SOURCE)
        self.assertIn('WUValidSurfaceStyles(all)', SOURCE)

if __name__ == '__main__':
    unittest.main()
