from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'Sources'

class IncrementalSafety(unittest.TestCase):
    def test_security_scope_lifetime_is_inside_worker(self):
        text = (ROOT / 'EmoticonLibrary.m').read_text()
        part = text.split('- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:')[1].split('- (void)use:')[0]
        self.assertLess(part.index('[self write:'), part.index('startAccessingSecurityScopedResource'))
        self.assertIn('@finally { if(scoped) [url stopAccessingSecurityScopedResource]; }', part)

    def test_style_reset_requires_confirmation(self):
        text = (ROOT / 'SurfaceSettings.m').read_text()
        part = text.split('if(p.section==2) {')[1].split('NSArray *field=self.fields[p.row]',1)[0]
        self.assertIn('UIAlertActionStyleCancel', part)
        self.assertIn('UIAlertActionStyleDestructive', part)
        self.assertIn('[self saveStyle:@{}]', part)

if __name__ == '__main__':
    unittest.main()
