"""Production wiring contracts; not a substitute for an on-device ABI/lifecycle test."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
submission = (ROOT / 'Sources/EmoticonSubmission.m').read_text()
ui = (ROOT / 'Sources/EmoticonLibrary.m').read_text()
binding = (ROOT / 'Sources/EmoticonLibraryBindings.inc').read_text()

class OfficialGIF(unittest.TestCase):
    def test_selected_and_confirmed_before_raw_read(self):
        b = ui.split('- (void)prepareSelectedOfficialGIF {', 1)[1].split('- (void)importMenu {', 1)[0]
        self.assertLess(b.index('UIAlertActionStyleCancel'), b.index('WUEmoticonRead(capture[@"path"])'))
        self.assertIn('if(used) return; used=YES;', b)
        self.assertIn('self.binding.selectionCurrent(capture)', b)
        self.assertIn('WUContextGenerationSnapshot()', b)
        self.assertIn('WUPrepareOfficialGIF(data,capture[@"md5"],valid)', b)
        self.assertIn('[selected firstObject]==wrap', binding)
        self.assertIn('检查所选GIF的微信添加条件（暂不提交）', ui)

    def test_wrapper_gate_and_no_guess_or_submission(self):
        b = submission.split('NSString *WUPrepareOfficialGIF(', 1)[1]
        for s in ('WUEmoticonType(bytes)', 'WUEmoticonDigest(bytes)', 'expectedMD5.lowercaseString',
                  '@"AddEmoticonWrap"', '@"EmojiInfoObj"', '@"EmoticonUploadInfoObj"',
                  '@"setFileType:"', '),@2)', 'Numeric(wrap,@"setSource:"',
                  'Numeric(wrap,@"setFileSize:"', 'Object(wrap,@"emojiInfoObj")!=emoji',
                  '!current()', '未向微信提交'):
            self.assertIn(s, b)
        for s in ('writeToFile:', 'setTempFilePath:', 'setUploadFilePath:', 'setDelegate:', 'objc_msgSend)(logic'):
            self.assertNotIn(s, b)

if __name__ == '__main__':
    unittest.main(verbosity=2)
