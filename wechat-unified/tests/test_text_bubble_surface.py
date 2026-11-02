"""Static guards for the scoped text-bubble projection; UIKit host validation remains required."""
import unittest
from pathlib import Path
R = Path(__file__).resolve().parents[1]
class TextBubble(unittest.TestCase):
    def test_wiring_and_ownership(self):
        for name in ('Core.m','ThemeCatalog.m','SurfaceSettings.m','Settings.m'):
            self.assertIn('@"textBubbleSurface"', (R/'Sources'/name).read_text())
        messages=(R/'Sources/Messages.m').read_text()
        surfaces=(R/'Sources/Surfaces.m').read_text()
        for token in ('type==1?@"textBubbleSurface"', 'Chat(cell)', 'WURestoreMessageSurface(cell)', 'WURestoreMessageSurface(a.cell)'):
            self.assertIn(token,messages)
        for token in ('TextMessageCellView','isKindOfClass:textClass','UIImageView.class','isDescendantOfView:cell','image]==imageState[@"applied"]','setImage:imageState[@"old"]','CGRectIsEmpty(imageView.bounds)'):
            self.assertIn(token,surfaces)
if __name__ == '__main__': unittest.main()
