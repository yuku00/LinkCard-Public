"""Static safety contracts; not a substitute for target-host animation testing."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class EmoticonSurfaceBoundary(unittest.TestCase):
    def test_only_identified_background_is_targeted(self):
        source = (ROOT / 'Sources/Surfaces.m').read_text()
        body = source.split('void WURefreshMessageSurface(', 1)[1].split('\n}', 1)[0]
        for guard in ('!cell.window', 'valueForKey:@"m_bgImageView"',
                      'UIImageView.class', 'target==cell', 'isDescendantOfView:cell',
                      'WUStyleSurface(target,role,14)'):
            self.assertIn(guard, body)
        self.assertIn('[role isEqual:@"textBubbleSurface"] && imageView.image', body)
        self.assertEqual(body.count('imageView.image=applied'), 1)
        for forbidden in ('animationImages', 'startAnimating', 'stopAnimating', 'setImage:', 'contents='):
            self.assertNotIn(forbidden, body)

    def test_restore_and_owned_value_guards(self):
        messages = (ROOT / 'Sources/Messages.m').read_text()
        for name in ('CellModel', 'CellWindow', 'CellLayout', 'CellReuse'):
            body = messages.split('static void ' + name + '(', 1)[1].split('\n}', 1)[0]
            self.assertIn('WURestoreMessageSurface(cell)', body)
        style = (ROOT / 'Sources/SurfaceStyle.m').read_text()
        self.assertIn('WUSurfaceValueOwned(Current(v,k),state[@"applied"][k])', style)
        self.assertIn('for(UIView *view in styledViews.allObjects) { WURestoreConfiguredSurface(view);', style)
        settings = (ROOT / 'Sources/SurfaceSettings.m').read_text()
        self.assertIn('不对表情本体裁圆角', settings)

if __name__ == '__main__':
    unittest.main()
