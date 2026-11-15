from pathlib import Path
import unittest

R = Path(__file__).resolve().parents[1]

class ToolbarSafety(unittest.TestCase):
    def test_no_chat_overlay_without_reserved_host_space(self):
        src = (R / 'Sources/Messages.m').read_text()
        sync = src.split('- (void)syncInputToolbar {', 1)[1].split('\n- (void)refresh {', 1)[0]
        self.assertIn('WUInputSyncChecked(owner,entries', sync)
        self.assertIn('WUInputRemove(owner)', sync)
        for guard in ('[account isEqual:Account()]', 'gen==generation', '[session isEqual:Session(v)]'):
            self.assertIn(guard, sync)
        self.assertNotIn('addSubview:toolbar', sync)
        self.assertNotIn('constraintEqualToAnchor:bar.topAnchor', sync)
        reservation = (R / 'Sources/WUInputReservation.inc').read_text()
        self.assertIn('WUInputReserved(', reservation)
        self.assertIn('WUInputStillSafe(s)', reservation)
        refresh = src.split('- (void)refresh {', 1)[1].split('\n- (void)openGrid {', 1)[0]
        self.assertIn('[items addObject:self.tools]', refresh)

    def test_release_includes_import_and_focused_tests(self):
        release = (R / 'tools/release.py').read_text()
        for path in ('Sources/ChatInputToolbar.inc', 'tests/chat_input_toolbar_ios.m', 'tools/test_chat_input_toolbar_ios.py', 'tests/test_chat_input_toolbar_safety.py'):
            self.assertIn(path, release)

if __name__ == '__main__': unittest.main()
