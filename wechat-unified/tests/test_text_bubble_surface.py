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
    def test_layout_reuse_and_model_restore_before_host(self):
        source=(R/'Sources/Messages.m').read_text()
        for name, original in (('CellLayout','cellLayoutOriginal'), ('CellReuse','cellReuseOriginal'),
                               ('CellModel','cellModelOriginal'), ('CellWindow','cellWindowOriginal')):
            body=source.split('static void '+name+'(',1)[1].split('\n}',1)[0]
            self.assertLess(body.index('WURestoreMessageSurface(cell)'), body.index('))'+original+')(cell,s'))
            if name=='CellLayout':
                self.assertLess(body.index('))cellLayoutOriginal)(cell,s'), body.index('WURefreshMessageSurface(cell'))

    def test_config_change_restores_images_without_action_registration(self):
        source=(R/'Sources/Surfaces.m').read_text()
        restore=source.split('void WURestoreMessageSurface(',1)[1].split('\n}',1)[0]
        refresh=source.split('void WURefreshMessageSurface(',1)[1].split('\n}',1)[0]
        observer=source.split('void WUInstallSurfaces(',1)[1].split('static dispatch_once_t popupOnce',1)[0]
        self.assertIn('textBubbleCells=NSHashTable.weakObjectsHashTable',observer)
        self.assertIn('for(UIView *cell in textBubbleCells.allObjects) { WURestoreMessageSurface(cell); [cell setNeedsLayout]; }',observer)
        self.assertIn('if(cell) [textBubbleCells removeObject:cell]',restore)
        self.assertLess(restore.index('image]==imageState[@"applied"]'), restore.index('setImage:imageState[@"old"]'))
        self.assertLess(refresh.index('[textBubbleCells addObject:cell]'), refresh.index('imageView.image=applied'))
        self.assertLess(refresh.index('[role isEqual:@"textBubbleSurface"] && imageView.image'), refresh.index('[textBubbleCells addObject:cell]'))

if __name__ == '__main__': unittest.main()
