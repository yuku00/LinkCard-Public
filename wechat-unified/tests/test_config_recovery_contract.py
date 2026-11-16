"""Portable wiring checks; behavioral disk tests are in p0_config.m (macOS Foundation)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT / 'Sources/Core.m').read_text()
SETTINGS = (ROOT / 'Sources/Settings.m').read_text()


class ConfigRecoveryContract(unittest.TestCase):
    def test_only_enoent_counts_as_missing(self):
        reader = CORE[CORE.index('static NSDictionary *ReadConfig('):CORE.index('static NSDictionary *LoadConfigSnapshot')]
        self.assertIn('if (missing) *missing=NO', reader)
        self.assertIn('errno==ENOENT', reader)
        self.assertIn('O_NOFOLLOW', reader)

    def test_initialization_and_write_fail_closed(self):
        loader = CORE[CORE.index('static NSDictionary *LoadConfigSnapshot'):CORE.index('static BOOL WriteConfig')]
        self.assertIn('configReadOnly=!loaded && !(mainMissing && backupMissing)', loader)
        self.assertIn('snapshot=LoadConfigSnapshot()', CORE)
        save = CORE[CORE.index('BOOL WUSave('):CORE.index('static const char *Unqualified')]
        self.assertLess(save.index('configReadOnly'), save.index('WriteConfig('))

    def test_settings_disclose_read_only_and_defaults(self):
        self.assertIn('WUConfigReadOnly()', SETTINGS)
        self.assertIn('当前显示安全默认值', SETTINGS)
        self.assertIn('已禁止保存并保留原文件', SETTINGS)


if __name__ == '__main__':
    unittest.main()
