"""Source-level guardrails; these do not replace on-device screenshots."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class NeoSearchAndTiles(unittest.TestCase):
    def test_search_remains_native_and_scoped(self):
        source = (ROOT / 'Sources/Settings.m').read_text()
        setup = source.split('UISearchController *search=', 1)[1].split('self.definesPresentationContext=YES;', 1)[0]
        for token in ('UISearchBarStyleMinimal', 'searchTextField.backgroundColor',
                      'searchTextField.layer.cornerRadius', 'self.navigationItem.searchController=search'):
            self.assertIn(token, setup)
        self.assertNotIn('frame=', setup)
        self.assertNotIn('appearance]', setup)

    def test_tiles_do_not_replace_existing_images(self):
        helper = (ROOT / 'Sources/WUNeoSettings.h').read_text()
        tile = helper.split('if(symbol.length && !cell.imageView.image)', 1)[1].split('if([cell.accessoryView', 1)[0]
        for token in ('UIGraphicsImageRenderer', 'UIImageRenderingModeAlwaysTemplate',
                      'systemIndigoColor', 'systemBlueColor', 'systemOrangeColor',
                      'isAccessibilityElement=NO'):
            self.assertIn(token, tile)
        for forbidden in ('UIAppearance', 'method_exchangeImplementations', 'navigationController.navigationBar'):
            self.assertNotIn(forbidden, tile)

if __name__ == '__main__':
    unittest.main()
