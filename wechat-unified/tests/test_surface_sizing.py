"""Source integration guards; UIKit behavior still requires an iOS runtime."""
from pathlib import Path
import unittest

root = Path(__file__).resolve().parents[1]

class SurfaceSizing(unittest.TestCase):
    def test_bounded_reversible_background_only(self):
        catalog = (root / 'Sources/ThemeCatalog.m').read_text()
        style = (root / 'Sources/SurfaceStyle.m').read_text()
        editor = (root / 'Sources/SurfaceSettings.m').read_text()
        for key in ('widthScale', 'heightScale'):
            self.assertIn('@"%s":@[@0.7,@1.3]' % key, catalog)
            self.assertIn('@"%s"' % key, editor)
            self.assertIn('s[@"%s"]' % key, style)
        for guard in ('UIImageView.class', '!v.userInteractionEnabled', 'textBubbleSurface', 'fileSurface', 'emoticonSurface', 'WUSurfaceValueOwned(Current(v,k),state[@"applied"][k])', 'CATransform3DScale(v.layer.transform,w,h,1)'):
            self.assertIn(guard, style)
        self.assertIn('label.transform=CGAffineTransformMakeScale(w,h)', editor)

if __name__ == '__main__': unittest.main()
