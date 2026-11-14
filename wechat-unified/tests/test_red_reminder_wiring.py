"""Static wiring checks only; UIKit delivery still needs an Apple mock/device test."""
from pathlib import Path
import unittest

source = (Path(__file__).resolve().parents[1] / 'Sources/Messages.m').read_text()
arrival = source[source.index('static void Arrival('):source.index('BOOL WUMessageAvailable(')]
pump = source[source.index('static void RedPump(void) {'):source.index('static void Arrival(')]

class RedReminderWiring(unittest.TestCase):
    def test_production_arrival_enqueues_bounded_metadata(self):
        for text in ('InSession(m,account,session)', 'WUOwnMessage(', 'redQueue.count>=64',
                     '@[account,session,messageID]', '[redQueue addObject:', 'RedPump();'):
            self.assertIn(text, arrival)
        self.assertNotIn('@"url":', arrival)
        self.assertNotIn('@"wrap":', arrival)

    def test_retry_expiry_and_presentation_acknowledgement(self):
        for text in ('age>60', 'redActive.presentingViewController', 'owner.transitionCoordinator',
                     'RedSchedule(); return;', 'completion:^{', '[redQueue removeObjectIdenticalTo:item]',
                     '[redSeen addObject:key]'):
            self.assertIn(text, pump)
        self.assertLess(pump.index('completion:^{'), pump.index('[redSeen addObject:key]'))

    def test_cancellation_and_local_only_position(self):
        self.assertIn('RedCancel();', source[source.index('static void CancelPending(void)'):source.index('static void Confirm(')])
        self.assertIn('![redAccount isEqual:current]', pump)
        self.assertIn('[Session(Chat(cell)) isEqual:session]', pump)
        self.assertIn('不会自动领取', pump)

if __name__ == '__main__':
    unittest.main()
