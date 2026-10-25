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
                         'typeSize.isAccessibilitySize', 'ScrollView {',
                         'minHeight: 44', '.height(420)',
                         'selection?.label', 'externaldrive.fill', 'xmark']:
            self.assertIn(fragment, SHEET)
        self.assertNotIn('BLEReaderIllustration', SHEET)
        self.assertNotIn('.ignoresSafeArea', SHEET)
        self.assertNotIn('.onDisappear', SHEET)
    def test_multiple_candidates_preserve_first_selection_until_user_switches(self):
        self.assertIn('@State private var selectedID: UUID?', SHEET)
        self.assertIn('selectedID = device.id', SHEET)
        self.assertIn('.pickerStyle(.menu)', SHEET)
        self.assertNotIn('Form {', SHEET)
        self.assertNotIn('.onChange(of: candidates', SHEET)
        self.assertIn('enabled: selection != nil && !ble.active', SHEET)
        self.assertIn('.disabled(!enabled)', SHEET)
        self.assertNotIn('.rssi', SHEET)
        self.assertIn('guard !initialized else { return }', SHEET)
    def test_minimal_sheet_and_real_saved_selection(self):
        for fragment in ['Toggle("自动连接此设备"', 'ble.preferences.trusted.contains',
                         'loadSelection()', 'ble.suggestedProfile(for: selected)',
                         'ble.status', '.buttonStyle(.borderedProminent)']:
            self.assertIn(fragment, SHEET)
        for fragment in ['DisclosureGroup', '.sheet(', 'BLEPreferencesView(ble:',
                         'setDiscoveryPrompt']:
            self.assertNotIn(fragment, SHEET)
        settings = UI[UI.index('struct BLEPreferencesView: View'):]
        for fragment in ['Picker("设备配置"', 'serviceUUID', 'showDiscoveryPrompt']:
            self.assertIn(fragment, settings)
        action = SHEET[SHEET.index('guard let selected = selection'):SHEET.index('}, onClose:', SHEET.index('guard let selected = selection'))]
        self.assertNotIn('cancelConnectionPrompt()', action)
        self.assertNotIn('dismiss()', action)
    def test_identify_feedback_and_real_modal_round_trips(self):
        view = (R/'LinkCard/LocalDeviceViews.swift').read_text()
        identify = view[view.index('private var identificationCard'):view.index('private var standardDeviceInformation')]
        self.assertIn('ble.identifyCard()', identify)
        self.assertIn('.frame(maxWidth: .infinity, minHeight: 44)', identify)
        self.assertIn('device.identify.disabledReason', identify)
        self.assertIn('Text(ble.identifyMessage)', identify)
        self.assertIn('.updatesFrequently', identify)
        for forbidden in ['confirmationDialog', '.sheet(', 'print(', 'try?']:
            self.assertNotIn(forbidden, identify)
        tests = (R/'LinkCardUITests/LinkCardFullAppTouchTests.swift').read_text()
        self.assertEqual(tests.count('    func test'), 4)
        self.assertEqual(tests.count('        verifyRealIdentifyGuard()'), 2)
        self.assertIn('device.settings.done', tests)
        self.assertIn('verifyPreviewPhotoPickerCancelAfterVerticalDrags()', tests)
if __name__ == '__main__': unittest.main()
