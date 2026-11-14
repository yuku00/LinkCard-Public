"""Check the actual stats translation unit's platform-dependent UIKit imports."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class StatsPlatformImports(unittest.TestCase):
    def test_foundation_only_macos_and_uikit_ios(self):
        clang = shutil.which('clang')
        if not clang:
            self.skipTest('clang unavailable')
        with tempfile.TemporaryDirectory() as temp:
            headers = Path(temp)
            for name in ('Foundation/Foundation.h', 'TargetConditionals.h', 'objc/runtime.h'):
                path = headers / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('')
            def preprocess(platform):
                return subprocess.run([clang, '-E', '-x', 'objective-c', '-I', temp,
                                       '-D', f'TARGET_OS_OSX={platform}',
                                       str(ROOT / 'Sources/WUStats.m')],
                                      text=True, capture_output=True)
            mac = preprocess(1)
            self.assertEqual(mac.returncode, 0, mac.stderr)
            self.assertNotIn('WUNeoPrepareTable', mac.stdout)
            ui = headers / 'UIKit/UIKit.h'
            ui.parent.mkdir()
            ui.write_text('/* synthetic UIKit for preprocessing only */\n')
            ios = preprocess(0)
            self.assertEqual(ios.returncode, 0, ios.stderr)
            self.assertIn('WUNeoPrepareTable', ios.stdout)
            self.assertIn('@implementation WUStatsController', ios.stdout)


if __name__ == '__main__':
    unittest.main()
