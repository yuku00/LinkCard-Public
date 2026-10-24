# SPDX-License-Identifier: GPL-3.0-or-later
"""Presentation source contracts, not screenshots or a hardware test."""
from pathlib import Path
import unittest
R = Path(__file__).resolve().parents[1]
UI = (R/'LinkCard/BLEPreferencesView.swift').read_text()
SHEET = UI[UI.index('private struct BLEConnectionConfirmation'):UI.index('struct BLEPreferencesView: View')]
class ConnectionSheetContracts(unittest.TestCase):
    def test_native_bottom_sheet_and_accessibility(self):
        for fragment in ['.presentationDetents(', '.presentationDragIndicator(.visible)',
                         'typeSize.isAccessibilitySize', 'Form {', 'NavigationStack {',
                         'minHeight: 44', '.height(380)',
                         'selection?.label', '.navigationBarTitleDisplayMode(.inline)']:
            self.assertIn(fragment, SHEET)
        self.assertNotIn('BLEReaderIllustration', SHEET)
        self.assertNotIn('.ignoresSafeArea', SHEET)
        self.assertNotIn('.onDisappear', SHEET)
    def test_multiple_candidates_need_explicit_choice(self):
        self.assertIn('@State private var selectedID: UUID?', SHEET)
        self.assertIn('if candidates.count == 1 { selectedID = device.id }', SHEET)
        self.assertIn('.disabled(selection == nil || ble.active)', SHEET)
        self.assertNotIn('.rssi', SHEET)
        self.assertIn('guard !initialized else { return }', SHEET)
    def test_safety_and_configuration_remain_available(self):
        for fragment in ['DisclosureGroup("高级")',
                         'BLEPreferencesView(ble: ble)', 'ble.preferences.profiles',
                         'ble.setDiscoveryPrompt(false)', '未知设备仍需手动确认',
                         '不会撤销信任', '不自动发送业务命令', '不是认证']:
            self.assertIn(fragment, SHEET)
        action = SHEET[SHEET.index('guard let selected = selection'):SHEET.index('} label: {', SHEET.index('guard let selected = selection'))]
        self.assertNotIn('cancelConnectionPrompt()', action)
        self.assertNotIn('dismiss()', action)
if __name__ == '__main__': unittest.main()
