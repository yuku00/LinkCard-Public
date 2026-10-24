"""Regression contracts for the real coordinator call sites (not radio tests)."""
from pathlib import Path
import unittest
R = Path(__file__).resolve().parents[1]
B = (R/'LinkCard/PCRBluetooth.swift').read_text()
U = (R/'LinkCard/LocalDeviceViews.swift').read_text()
H = (R/'LinkCard/BLEPreferencesView.swift').read_text()
class SessionRegression(unittest.TestCase):
    def test_normal_information_completion_keeps_link(self):
        end = B.split('guard !informationQueue.isEmpty else {')[1].split('return')[0]
        self.assertNotIn('disconnect(', end)
        self.assertIn('finishQuery(', end)
    def test_normal_version_completion_keeps_link(self):
        end = B.split('if let version = try parser.feed(value) {')[1].split('}')[0]
        self.assertNotIn('disconnect(', end)
        self.assertIn('finishQuery(', end)
    def test_tab_does_not_own_connection(self):
        self.assertNotIn('.onDisappear { ble.disconnect', U)
    def test_only_background_ends_session(self):
        self.assertNotIn('ble.setForeground($0 == .active)', H)
        self.assertIn('case .background: ble.setForeground(false)', H)
        self.assertIn('case .inactive: break', H)
    def test_manual_suppression_and_timeouts_retained(self):
        self.assertIn('if suppressSession { sessionSuppressed = true; retryAfterDisconnect = false }', B)
        for deadline in ('arm(12)', 'arm(15)', 'arm(4)'):
            self.assertIn(deadline, B)
    def test_finish_clears_request_not_subscriptions(self):
        body = B.split('func finishQuery(')[1].split('func readVersion')[0]
        for text in ('busy = false', 'readingDeviceInformation = false', 'pendingInformation = nil', 'deadline?.cancel()'):
            self.assertIn(text, body)
        for text in ('cancelPeripheralConnection', 'rx = nil', 'setNotifyValue(false'):
            self.assertNotIn(text, body)
if __name__ == '__main__': unittest.main()
