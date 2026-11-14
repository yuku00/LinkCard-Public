"""Static lifecycle guard; UIKit and host behavior require device validation."""
from pathlib import Path
import unittest

S = (Path(__file__).resolve().parents[1] / 'Sources/Surfaces.m').read_text()

class ChildSurfaceRefresh(unittest.TestCase):
    def test_roots_tracked_even_when_role_disabled(self):
        time = S[S.index('static void Time('):S.index('static void Swipe(')]
        swipe = S[S.index('static void Swipe('):S.index('// 8.0.55 public headers')]
        for body, role, original in ((time, 'timeSurface', 'timeLayout'), (swipe, 'swipeSurface', 'swipeLayout')):
            self.assertLess(body.index('RestoreChildren(v)'), body.index(original + ')(v,s)'))
            self.assertLess(body.index('[childSurfaceRoots addObject:v]'), body.index('if(!WUEnabled(@"' + role + '")) return'))
        self.assertIn('childSurfaceRoots=NSHashTable.weakObjectsHashTable', S)
        self.assertIn('for(UIView *root in childSurfaceRoots.allObjects) { RestoreChildren(root); [root setNeedsLayout]; }', S)
        self.assertIn('addObserverForName:WUChanged', S)

if __name__ == '__main__': unittest.main()
