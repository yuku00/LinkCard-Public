# SPDX-License-Identifier: GPL-3.0-or-later
"""Source guards, NOT an iOS gesture/hang reproduction or runtime proof."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

class VerticalWorkbenchContracts(unittest.TestCase):
    def test_stable_coordinates_and_one_transient_owner(self):
        shell = (ROOT / 'LinkCard/FusionShell.swift').read_text()
        self.assertIn('coordinateSpace: .named("workbench.shell")', shell)
        self.assertIn('@GestureState private var handleDrag: FusionWorkbenchDrag?', shell)
        self.assertNotIn('@State private var dragProgress', shell)
        self.assertNotIn('handleOrigin', shell)
        self.assertIn('if sample != next { sample = next }', shell)
        self.assertIn('transaction.disablesAnimations = true', shell)
        self.assertNotIn('withAnimation(', shell)
        self.assertEqual(shell.count('.animation('), 1)
        self.assertIn('value: progress', shell)
        self.assertIn('if workbench.expanded != expanded', shell)
        self.assertEqual(shell.count('.highPriorityGesture('), 1)
        self.assertIn('guard let sample = handleSession.start', shell)

    def test_frozen_geometry_and_no_content_scroll_hijack(self):
        shell = (ROOT / 'LinkCard/FusionShell.swift').read_text()
        motion = (ROOT / 'LinkCard/FusionMotion.swift').read_text()
        self.assertIn('struct FusionWorkbenchDrag: Equatable', motion)
        self.assertIn('let travel: CGFloat', motion)
        self.assertIn('let vertical: Bool', motion)
        self.assertIn('matches(size: size, keyboard: keyboard', shell)
        content = shell.split('Group {\n                if !state.search.isEmpty', 1)[1].split('private var tabs:', 1)[0]
        self.assertNotIn('Gesture(', content)
        root = (ROOT / 'LinkCard/ContentView.swift').read_text()
        self.assertIn('workbench.frames = frames', root)
        theme = (ROOT / 'LinkCard/MistDesign.swift').read_text()
        self.assertIn('var frames: [String: CGRect] = [:]', theme)
        self.assertNotIn('@Published var frames', theme)

    def test_real_vertical_ui_tests_are_not_click_substitutes(self):
        tests = (ROOT / 'LinkCardUITests/LinkCardFullAppTouchTests.swift').read_text()
        for name in ['verifyWorkbenchVerticalHandleRoundTripsAndReversal',
                     'verifyWorkbenchVerticalContentScrollAndSettingsHandle',
                     'verifyWorkbenchVerticalWithKeyboardAndLifecycle',
                     'verifyFourBlurChannelsRemainIndependentAcrossRelaunch']:
            self.assertIn('func ' + name, tests)
        self.assertIn('thenDragTo: screenPoint(', tests)
        self.assertIn('responsiveTabTap()', tests)
        for forbidden in ['sendActions(', 'waitForQuiescence = false', 'waitForIdleTimeout = 0']:
            self.assertNotIn(forbidden, tests)
        self.assertEqual(len(re.findall(r'    func test\w+\(', tests)), 4)
        self.assertIn('verifyPreviewPhotoPickerCancelAfterVerticalDrags', tests)
        self.assertIn('verifySendConfirmationPreferencePersistsWithoutStartingNFC', tests)

    def test_sidebar_has_own_key_and_single_material_owner(self):
        theme = (ROOT / 'LinkCard/MistDesign.swift').read_text()
        shell = (ROOT / 'LinkCard/FusionShell.swift').read_text()
        self.assertIn('appearance.blur.sidebar.v1', theme)
        self.assertIn('if defaults.object(forKey: Self.sidebarKey) == nil', theme)
        self.assertIn('case .sidebar: return sidebar', theme)
        self.assertIn('strength: cardBlur.strength(channel: .sidebar)', shell)
        for name in ['controls', 'sidebar', 'workbench', 'wallpaper']:
            self.assertEqual(theme.count('accessibilityIdentifier("blur.' + name + '")'), 1)
        drawer = shell.split('private func drawer()', 1)[1]
        self.assertNotIn('MistSurface(', drawer)
        self.assertNotIn('.blur(', drawer)

    def test_photo_defaults_preview_picker_and_transactional_import(self):
        root = (ROOT / 'LinkCard/ContentView.swift').read_text()
        self.assertIn('@State private var dither = true', root)
        self.assertIn('dither: source == 0 && dither', root)
        self.assertIn('Toggle("细腻抖动", isOn: $dither)', root)
        preview = root.split('private func preview(', 1)[1].split('private var transferStatus', 1)[0]
        self.assertIn('Button { choosePhoto() } label:', preview)
        self.assertEqual(root.count('.photosPicker(isPresented: $photoPickerPresented, selection: $selected, matching: .images)'), 1)
        self.assertIn('.buttonStyle(.plain)', preview)
        self.assertIn('.disabled(nfc.busy || sendRequest.dispatched || loading || photoPickerPresented)', preview)
        self.assertNotIn('onTapGesture', preview)
        choose = root.split('private func choosePhoto()', 1)[1].split('private func loadPhoto()', 1)[0]
        for forbidden in ['source =', 'photo =', 'rendered =', 'dither =']:
            self.assertNotIn(forbidden, choose)
        self.assertIn('selected = nil', choose)
        loader = root.split('private func loadPhoto()', 1)[1].split('private func updatePreview()', 1)[0]
        self.assertIn('if item == importedSelection', loader)
        self.assertIn('selected == item', loader)
        self.assertNotIn('rendered = nil', loader)
        self.assertNotIn('photo = nil', loader)
        self.assertGreater(loader.rindex('source = 0'), loader.index('CardRenderer.photo(data: data)'))
        self.assertNotIn('nfc.send(', loader)

    def test_confirm_and_direct_send_share_snapshot_and_core_nfc_path(self):
        root = (ROOT / 'LinkCard/ContentView.swift').read_text()
        self.assertIn('@AppStorage("nfc.confirmBeforeSend.v1") private var confirmBeforeSend = true', root)
        self.assertEqual(root.count('nfc.send(frame: frame)'), 1)
        self.assertIn('case .send: dispatchPreparedSend()', root)
        self.assertIn('Button("通过 NFC 发送") { dispatchPreparedSend() }', root)
        self.assertIn('Button("取消", role: .cancel) { sendRequest.cancel() }', root)
        self.assertIn('sendRequest.takeFrame(busy: nfc.busy, loading: loading', root)
        self.assertIn('snapshot.count == 5000', root)
        self.assertIn('self.frame == nil, !busy, !loading, !previewPending', root)
        self.assertIn('sendRequest.dispatched || confirmSend', root)
        self.assertIn('不会隐藏系统 NFC 界面', root)

if __name__ == '__main__':
    unittest.main()
