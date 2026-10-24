"""Offline source guards, NOT a UIKit/crash reproduction. Run with unittest."""
from pathlib import Path
import os
import unittest

ROOT = Path(os.environ.get('LINKCARD_SOURCE_ROOT', Path(__file__).resolve().parents[1]))

class EffectLifecycleContracts(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'LinkCard/MistDesign.swift').read_text()
        self.effect = self.source.split('final class MistEffectView:', 1)[1].split('private struct MistBackdrop:', 1)[0]

    def test_no_unfinished_animation_or_private_filter(self):
        for token in ['UIViewPropertyAnimator', 'fractionComplete', 'pauseAnimation(', 'setValue(', 'CAFilter', 'layer.filters']:
            self.assertNotIn(token, self.effect)
        self.assertIn('UIBlurEffect(style: .systemUltraThinMaterial)', self.effect)
        self.assertIn('visualTint', self.effect)
        self.assertIn('withAlphaComponent', self.effect)
        self.assertNotIn('.alpha =', self.effect)

    def test_stationary_update_and_input_guard(self):
        self.assertIn('value.isFinite', self.effect)
        self.assertIn('guard !isRebuilding else { return }', self.effect)
        self.assertIn('if effect == nil', self.effect)

    def test_dismantle_cannot_reactivate(self):
        stop = self.effect.split('func stopEffect()', 1)[1].split('\n    }', 1)[0]
        self.assertIn('intensity = 0', stop)
        self.assertIn('clearEffect()', stop)

    def test_clock_has_minute_boundary_schedule_not_second_tree_updates(self):
        clock = (ROOT / 'LinkCard/FusionGeometry.swift').read_text().split('struct FusionClock:', 1)[1]
        self.assertIn('TimelineView(.everyMinute)', clock)
        self.assertNotIn('by: 1)', clock)

    def test_numeric_defaults_include_argument_domain_strings(self):
        self.assertIn('Double(text)', self.source)
        self.assertIn('Self.readStrength(defaults, key: Self.controlsKey)', self.source)
        self.assertIn('Self.readStrength(defaults, key: Self.workbenchKey)', self.source)

    def test_no_app_accessibility_fallback(self):
        for token in ['accessibilityReduceTransparency', 'colorSchemeContrast', '.disabled(paused)', '!reduceTransparency', 'if paused']:
            self.assertNotIn(token, self.source)
        self.assertIn('if let image = store.image {', self.source)
        self.assertIn('Color.black.opacity(0.70)', self.source)
        self.assertIn('Color.white.opacity(0.82)', self.source)

if __name__ == '__main__':
    unittest.main()
