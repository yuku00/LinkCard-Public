from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'Sources/Messages.m').read_text()

class MergeLifecycleContract(unittest.TestCase):
    def test_model_window_layout_and_reuse_restore_first(self):
        for name, original in [('CellModel', 'cellModelOriginal'), ('CellWindow', 'cellWindowOriginal'),
                               ('CellLayout', 'cellLayoutOriginal'), ('CellReuse', 'cellReuseOriginal')]:
            body = SOURCE.split('static void ' + name + '(', 1)[1].split('\n}', 1)[0]
            self.assertLess(body.index(' restore]'), body.index(original), name)

    def test_restore_does_not_overwrite_unhidden_host_views(self):
        body = SOURCE.split('- (void)restore {', 1)[1].split('\n}', 1)[0]
        self.assertIn('if(self.head.hidden) self.head.hidden=self.headHidden', body)
        self.assertIn('if(self.name.hidden) self.name.hidden=self.nameHidden', body)
        self.assertIn('self.head=nil; self.name=nil', body)

    def test_only_hide_descendants(self):
        body = SOURCE.split('id head=KnownValue(cell,@"m_headImageView")', 1)[1].split('\n}', 1)[0]
        self.assertIn('head==cell || ![head isDescendantOfView:cell]', body)
        self.assertIn('name!=cell && [name isDescendantOfView:cell]', body)

if __name__ == '__main__':
    unittest.main()
