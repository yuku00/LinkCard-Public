"""Source contracts complement (never replace) the four real XCTest gates."""
from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'LinkCardUITests/LinkCardFullAppTouchTests.swift'

class TouchTargetContracts(unittest.TestCase):
    def test_dither_uses_leaf_switch_and_two_single_taps(self):
        s = SOURCE.read_text()
        self.assertIn('visibleLeafControl(ditherRow, type: .switch)', s)
        self.assertIn('descendants(matching: type).count == 0', s)
        self.assertIn('candidates.count, 1', s)
        self.assertIn('row.elementType == type ? [row] : []', s)
        self.assertIn('control.isHittable', s)
        self.assertNotIn('insetBy(dx: -1', s)
        self.assertNotIn('f.width <= 3 * f.height', s)
        self.assertEqual(s.count('tap(dither)'), 2)
        self.assertIn('XCTAssertNotEqual(dither.value as? String, originalDither', s)
        self.assertIn('XCTAssertEqual(dither.value as? String, originalDither', s)
        self.assertIn('waitForValue(dither, row: ditherRow, expected: changedDither)', s)
        self.assertIn('waitForValue(dither, row: ditherRow, expected: original)', s)
        self.assertNotIn('353.5', s)

    def test_sliders_resolve_leaf_and_prefer_ax_thumb(self):
        s = SOURCE.read_text()
        self.assertIn('visibleLeafControl(row, type: .slider)', s)
        self.assertIn('thumb.frame', s)
        self.assertIn('slider.adjust(toNormalizedSliderPosition: position)', s)
        self.assertIn('A real thumb drag must change the setting', s)
        self.assertNotIn('f.width - 28', s)

    def test_full_four_cases_and_default_wait_remain(self):
        s = SOURCE.read_text()
        self.assertEqual(s.count('    func test'), 4)
        for forbidden in ['XCTSkip', 'waitForQuiescence = false', 'animationsEnabled = false', 'setValue(']:
            self.assertNotIn(forbidden, s)
        for name in ['blur.wallpaper', 'blur.controls', 'blur.workbench', '通过 NFC 发送', 'device.read']:
            self.assertIn(name, s)

if __name__ == '__main__':
    unittest.main()
