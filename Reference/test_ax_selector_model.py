"""Pure AX selector regression: geometry is NOT semantic ownership.
All rectangles are deliberately synthetic, not device or diagnostic captures.
This model supplements, and never replaces, the real four-case XCUI gate.
"""
from dataclasses import dataclass, field
import unittest

@dataclass
class AX:
    kind: str
    frame: tuple
    identifier: str = ''
    hittable: bool = True
    exists: bool = True
    enabled: bool = True
    children: list = field(default_factory=list)

    def descendants(self, kind):
        result = []
        for child in self.children:
            if child.kind == kind:
                result.append(child)
            result.extend(child.descendants(kind))
        return result


def synthetic_tree():
    leaf = AX('switch', (100, 20, 34, 24))
    row = AX('switch', (10, 20, 120, 30),
             'create.dither', children=[leaf])
    return row, leaf


def old_select(row, kind):
    descendants = row.descendants(kind)
    candidates = []
    for e in descendants or [row]:
        x,y,w,h = e.frame
        rx,ry,rw,rh = row.frame
        if (e.exists and e.hittable and w > 0 and h > 0
                and not e.descendants(kind)
                and rx-1 <= x and ry-1 <= y
                and rx+rw+1 >= x+w and ry+rh+1 >= y+h
                and (kind != 'switch' or h <= w <= 3*h)):
            candidates.append(e)
    return candidates[0] if len(candidates) == 1 else None


def select(row, kind):
    descendants = row.descendants(kind)
    pool = descendants if descendants else ([row] if row.kind == kind else [])
    leaves = [e for e in pool if e.exists and not e.descendants(kind)]
    if len(leaves) != 1:
        return None
    leaf = leaves[0]
    _,_,w,h = leaf.frame
    return leaf if leaf.hittable and leaf.enabled and w > 0 and h > 0 else None


class AXSelectorModelTests(unittest.TestCase):
    def test_synthetic_old_red_new_green(self):
        row, leaf = synthetic_tree()
        self.assertLess(row.frame[0]+row.frame[2]+1, leaf.frame[0]+leaf.frame[2])
        self.assertIsNone(old_select(row, 'switch'))
        self.assertIs(select(row, 'switch'), leaf)

    def test_outer_itself_can_be_native_leaf(self):
        _, leaf = synthetic_tree()
        leaf.identifier = 'create.dither'
        self.assertIs(select(leaf, 'switch'), leaf)

    def test_intermediate_wrappers_are_not_touch_targets(self):
        row, leaf = synthetic_tree()
        row.children = [AX('other', (0,0,1,1), children=[AX('switch', (0,0,2,2), children=[leaf])])]
        self.assertIs(select(row, 'switch'), leaf)

    def test_wrong_parent_cannot_borrow_nearby_switch(self):
        row, leaf = synthetic_tree()
        wrong = AX('other', row.frame, 'unrelated')
        app = AX('application', (0,0,393,852), children=[wrong,row])
        self.assertIn(leaf, app.descendants('switch'))
        self.assertIsNone(select(wrong, 'switch'))

    def test_duplicate_leaf_rejected_even_if_one_hidden(self):
        row, _ = synthetic_tree()
        row.children.append(AX('switch', (100,20,34,24)))
        self.assertIsNone(select(row, 'switch'))
        row.children[1].hittable = False
        self.assertIsNone(select(row, 'switch'))

    def test_missing_and_wrong_type_rejected(self):
        row = AX('other', (10,20,120,30), 'create.dither')
        self.assertIsNone(select(row, 'switch'))
        row.children = [AX('slider', (100,20,34,24))]
        self.assertIsNone(select(row, 'switch'))

    def test_nonhittable_disabled_empty_nonexistent_rejected(self):
        for field_name, value in [('hittable',False),('enabled',False),('exists',False),('frame',(100,20,0,24))]:
            with self.subTest(field=field_name):
                row, leaf = synthetic_tree()
                setattr(leaf, field_name, value)
                self.assertIsNone(select(row, 'switch'))

    def test_slider_descendant_ownership_not_frame_containment(self):
        leaf = AX('slider', (8,60,124,32))
        row = AX('slider', (10,60,120,30), 'blur.wallpaper', children=[leaf])
        self.assertIsNone(old_select(row, 'slider'))
        self.assertIs(select(row, 'slider'), leaf)

if __name__ == '__main__':
    unittest.main()
