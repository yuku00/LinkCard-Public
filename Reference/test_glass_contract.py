# SPDX-License-Identifier: GPL-3.0-or-later
"""Source and numeric design contracts, NOT SwiftUI/runtime/hardware tests."""
from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]
def source(name): return (R/'LinkCard'/name).read_text()
def luminance(rgb):
    return sum(w*(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4) for w,v in zip((.2126,.7152,.0722),rgb))
def contrast(a,b):
    lo,hi=sorted((luminance(a),luminance(b))); return (hi+.05)/(lo+.05)
class GlassContracts(unittest.TestCase):
    def test_no_default_lists(self):
        for f in ('ContentView.swift','LocalDeviceViews.swift'):
            self.assertNotIn('List {',source(f));self.assertIn('MistPage(',source(f))
    def test_persistent_owners(self):
        s=source('ContentView.swift')
        for owner in ('nfc = NFCService()', 'ble = PCRBluetooth()', 'library = LocalCardLibrary()', 'wallpaper = WallpaperStore()'):
            self.assertIn('@StateObject private var '+owner,s)
        self.assertIn('@State private var text',s)
        self.assertIn('pendingFrame = rendered?.frame',s)
        self.assertIn('guard let frame = pendingFrame',s)
    def test_native_material_and_accessibility(self):
        s=source('MistDesign.swift')
        for feature in ('UIVisualEffectView','visualTint.backgroundColor','UIBlurEffect(style: .systemUltraThinMaterial)','dynamicTypeSize'):
            self.assertIn(feature,s)
        self.assertNotIn('.glassEffect',s)
    def test_keyboard_safe_area_and_preview(self):
        s=source('ContentView.swift') + source('FusionShell.swift')
        for feature in ('VStack(spacing: 0)', 'recordWorkbenchFrame("tabs")', 'if !keyboardVisible','keyboardWillHideNotification','.frame(width: side, height: side)', '.interpolation(.none)'):
            self.assertIn(feature,s)
    def test_wallpaper_local_separate_and_bounded(self):
        s=source('MistDesign.swift')
        for feature in ('CGImageSourceCreateThumbnailAtIndex', '1800', '.completeFileProtection','isExcludedFromBackup = true','Task.checkCancellation()', 'PhotosPicker'):
            self.assertIn(feature,s)
        for excluded in ('URLSession','NFCService','PCRBluetooth','CardRenderer.render','LocalCards'):
            self.assertNotIn(excluded,s)
    def test_candidate_is_not_authorization(self):
        s=source('PCRBluetooth.swift')
        self.assertIn('canQuery = PCRRoute.allowsText(selected?.name ?? "")',s)
        self.assertIn('scanForPeripherals(withServices: nil',s)
        self.assertIn('devices = [] // Clear stale',s)
        # Standard GATT reads now require explicit user action and a fixed whitelist.
        self.assertEqual(s.count('peripheral.readValue(for:'), 1)
        self.assertIn('guard connected, canReadDeviceInformation, !busy, !closing', s)
        self.assertIn('CBUUID(string: "180A")', s)
        self.assertIn('informationCharacteristics = PCRDeviceInformation.fields.compactMap', s)
        self.assertIn('$0.properties.contains(.read)', s)
        fields = source('PCRProtocol.swift').split('static let fields:', 1)[1].split('static func displayValue', 1)[0]
        import re
        self.assertEqual(re.findall(r'"(2A[0-9A-F]{2})"', fields), ['2A24', '2A27', '2A28', '2A29'])
        self.assertNotIn('"2A25"', s)
        d=source('LocalDeviceViews.swift')
        self.assertIn('Button { ble.readDeviceInformation() }', d)
        self.assertIn('.disabled(!ble.canReadDeviceInformation || ble.busy)', d)
        self.assertIn('ForEach(PCRDeviceInformation.fields, id: \\.uuid)', d)
        self.assertIn('显示其他设备',d)
        self.assertNotIn('onDisappear { ble.disconnect',d)
        self.assertIn('device.label',d)
    def test_copy_has_no_identifier_or_characteristic_values(self):
        s=source('LocalDeviceViews.swift').split('private func copyDiagnostics',1)[1].split('private struct ExportedCard',1)[0]
        self.assertIn('device.label',s);self.assertIn('ble.services',s)
        for secret in ('identifier','maskedID','.value','ble.result'):
            self.assertNotIn(secret,s)
    def test_conservative_panel_contrast(self):
        # Worst possible RGB underlay before the fixed panel veil; ignores any
        # further contrast improvement supplied by Apple's Material.
        self.assertGreaterEqual(contrast((.26,.34,.43),(.82,)*3),4.5)
        self.assertGreaterEqual(contrast((.77,.83,.90),(.30,)*3),4.5)
        self.assertGreaterEqual(contrast((1,)*3,(.12,.36,.68)),4.5)
if __name__=='__main__': unittest.main()
