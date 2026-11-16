from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOME = (ROOT / 'Sources/HomeGroups.m').read_text()
INPUT = (ROOT / 'Sources/WUInputReservation.inc').read_text()

class StartupRegression(unittest.TestCase):
    def test_home_can_seed_after_initial_setters(self):
        snapshot = HOME[HOME.index('static WUHomeSnapshot *Snapshot('):HOME.index('static void Refresh(void);')]
        self.assertIn('NSSelectorFromString(@"totalTopSessionCount")', snapshot)
        self.assertIn('WUMatches(countGetter,"q",@[])', snapshot)
        self.assertIn('WUMatches(countGetter,"Q",@[])', snapshot)
        self.assertIn('s.countKnown=YES', snapshot)
        refresh = HOME[HOME.index('- (void)refresh {\n    Class home='):HOME.index('- (void)select:')]
        self.assertIn('ready && a.length?CurrentManager():nil', refresh)
        self.assertIn('if(prior && !prior.filtered && ![prior.account isEqual:a])', refresh)
        self.assertIn('(void)Snapshot(manager);', refresh)
        self.assertIn('available=s.filtered', refresh)

    def test_only_noninteractive_background_image_is_ignored(self):
        clear = INPUT[INPUT.index('static BOOL WUInputClear('):INPUT.index('static BOOL WUInputStillSafe(')]
        self.assertIn('[child isKindOfClass:UIImageView.class]', clear)
        self.assertIn('!child.userInteractionEnabled', clear)
        self.assertIn('indexOfObjectIdenticalTo:child]<[container.subviews indexOfObjectIdenticalTo:except]', clear)
        self.assertIn('CGRectIntersectsRect', clear)

if __name__ == '__main__':
    unittest.main()
