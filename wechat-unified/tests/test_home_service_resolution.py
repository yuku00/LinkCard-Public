from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class HomeServiceResolution(unittest.TestCase):
    def test_home_managers_resolve_through_account_context(self):
        source = (ROOT / 'Sources/HomeGroups.m').read_text()
        self.assertIn('#import "WUHostService.h"', source)
        self.assertIn('WUHostService(@"MainSessionMgr")', source)
        self.assertIn('WUHostService(@"MMNewSessionMgr")', source)
        self.assertNotIn('@"MMServiceCenter"', source)

if __name__ == '__main__':
    unittest.main()
