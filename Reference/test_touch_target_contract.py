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

    def test_slider_overshoot_uses_two_measured_points_not_repeated_offset(self):
        s = SOURCE.read_text()
        self.assertIn('let response = secondLanding - landed', s)
        self.assertIn('let fraction = (position - landed) / response', s)
        self.assertIn('let interpolated = position + (corrected - position) * fraction', s)
        self.assertIn('(0...1).contains(fraction)', s)
        self.assertEqual(s.count('slider.adjust(toNormalizedSliderPosition:'), 3)
        self.assertIn('accuracy: 0.02', s)
        # Observed pair: request .18 -> .15; request .21 -> .21.
        # A repeated full offset would return to .18 and can oscillate.
        target, first, requested, second = .18, .15, .21, .21
        fraction = (target - first) / (second - first)
        interpolated = target + (requested - target) * fraction
        self.assertAlmostEqual(interpolated, .195)
        self.assertTrue(target < interpolated < requested)

    def test_full_four_cases_and_default_wait_remain(self):
        s = SOURCE.read_text()
        self.assertEqual(s.count('    func test'), 4)
        for forbidden in ['XCTSkip', 'waitForQuiescence = false', 'animationsEnabled = false', 'setValue(']:
            self.assertNotIn(forbidden, s)
        for name in ['blur.wallpaper', 'blur.controls', 'blur.workbench', '通过 NFC 发送', 'device.read']:
            self.assertIn(name, s)

if __name__ == '__main__':
    unittest.main()
