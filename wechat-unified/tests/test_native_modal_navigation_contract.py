from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class NativeModalNavigationContract(unittest.TestCase):
    def test_validation_uses_stack_top_not_modal_visible_controller(self):
        source = (ROOT / 'Sources/WUNativeAction.m').read_text()
        start = source.index('- (BOOL)isValid')
        end = source.index('- (BOOL)present', start)
        validity = source[start:end]
        self.assertIn('navigationController.topViewController==self.owner', validity)
        self.assertNotIn('navigationController.visibleViewController==self.owner', validity)

if __name__ == '__main__':
    unittest.main()
