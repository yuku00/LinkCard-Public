# SPDX-License-Identifier: GPL-3.0-or-later
"""Source-level UI invariants only; these do not simulate UIKit backdrop rendering."""
from pathlib import Path
import re
import unittest
R = Path(__file__).resolve().parents[1]
def read(name): return (R/'LinkCard'/name).read_text()

class CardBlurContracts(unittest.TestCase):
    def test_every_glass_card_has_registered_stable_identity(self):
        theme = read('MistDesign.swift')
        pages = theme + read('ContentView.swift') + read('LocalDeviceViews.swift') + read('FusionShell.swift')
        self.assertNotRegex(pages, r'MistPanel\s*\{')
        registry = re.findall(r'\.init\(id: "([^"]+)"', theme)
        self.assertEqual(len(registry), len(set(registry)))
        used = re.findall(r'Mist(?:Panel|Surface)\(id: "([^"]+)"', pages)
        self.assertTrue(set(registry).issubset(set(used)))
        self.assertEqual(len(registry), 16)
        self.assertIn('MistPanel(id: MistCardTarget.library(card.id))', pages)
        identity = theme.split('static func library', 1)[1].split('\n}', 1)[0]
        self.assertNotIn('UUID()', identity)
        self.assertNotIn('.name', identity)

    def test_background_only_public_api(self):
        theme = read('MistDesign.swift')
        for token in ['UIBlurEffect(style: .systemUltraThinMaterial)', 'visualTint.backgroundColor', '.background { MistSurface(id: id) }']:
            self.assertIn(token, theme)
        for token in ['setValue(', 'value(forKey:', 'CAFilter', 'layer.filters', 'contentView.addSubview']:
            self.assertNotIn(token, theme)
        for file in ['ContentView.swift', 'LocalDeviceViews.swift']:
            self.assertNotIn('.blur(', read(file))
        self.assertEqual(theme.count('.blur('), 1)  # wallpaper only
        self.assertNotIn('.regularMaterial', theme)
        self.assertNotIn('.thickMaterial', theme)

    def test_lifecycle_and_accessibility(self):
        theme = read('MistDesign.swift')
        for token in ['didMoveToWindow', 'traitCollectionDidChange', 'didBecomeActiveNotification', 'dismantleUIView', 'clearEffect()', 'removeObserver(self)', 'if intensity == 0', 'if window == nil']:
            self.assertIn(token, theme)
        self.assertIn('Color.black.opacity(0.70)', theme)
        self.assertIn('Color.white.opacity(0.82)', theme)

    def test_shared_store_and_persistence_namespace(self):
        theme = read('MistDesign.swift')
        root = read('ContentView.swift')
        self.assertIn('@StateObject private var cardBlur = MistBlurStore()', root)
        self.assertIn('.environmentObject(cardBlur)', root)
        self.assertIn('@EnvironmentObject private var blur: MistBlurStore', theme)
        for key in ['appearance.cardBlur.global.v1', 'appearance.cardBlur.overrides.v1', 'appearance.blur', 'appearance.veil']:
            self.assertIn(key, theme)
        for text in ['恢复此卡跟随全局', '恢复全部卡片默认设置', '跟随全局', 'setOverride(', 'var overrides']:
            self.assertNotIn(text, theme)
        for key in ['appearance.blur.controls.v2', 'appearance.blur.workbench.v2', 'appearance.blur.migrated.v2']:
            self.assertIn(key, theme)
        for slider in ['blur.controls', 'blur.workbench', 'blur.wallpaper']:
            self.assertEqual(theme.count('accessibilityIdentifier("' + slider + '")'), 1)
        self.assertIn('if !inWorkbench || id == "action"', theme)

if __name__ == '__main__': unittest.main()
