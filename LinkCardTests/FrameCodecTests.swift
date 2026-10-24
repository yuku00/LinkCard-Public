// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import UIKit
import SwiftUI
@testable import LinkCard

final class FrameCodecTests: XCTestCase {
    func testWhiteAndBlack() throws {
        XCTAssertEqual(try FrameCodec.encode([UInt8](repeating: 255, count: 40000)), Data(repeating: 255, count: 5000))
        XCTAssertEqual(try FrameCodec.encode([UInt8](repeating: 0, count: 40000)), Data(repeating: 0, count: 5000))
    }
    func testUpperLeftWhite() throws {
        var pixels = [UInt8](repeating: 0, count: 40000); pixels[0] = 255
        var expected = Data(repeating: 0, count: 5000); expected[4975] = 0x80
        XCTAssertEqual(try FrameCodec.encode(pixels), expected)
    }
    func testUpperLeftBlack() throws {
        var pixels = [UInt8](repeating: 255, count: 40000); pixels[0] = 0
        var expected = Data(repeating: 255, count: 5000); expected[4975] = 0x7F
        XCTAssertEqual(try FrameCodec.encode(pixels), expected)
    }
    func testLowerRightAndBitOrder() throws {
        var pixels = [UInt8](repeating: 0, count: 40000); pixels[39999] = 255
        var expected = Data(repeating: 0, count: 5000); expected[24] = 1
        XCTAssertEqual(try FrameCodec.encode(pixels), expected)
        pixels[39800..<39808] = [255, 0, 255, 0, 0, 255, 0, 255][...]
        XCTAssertEqual(try FrameCodec.encode(pixels)[0], 0xA5)
    }
    func testPacketsAndInvalidInput() throws {
        let data = Data(repeating: 0x5A, count: 5000)
        let parts = try FrameCodec.packets(data)
        XCTAssertEqual(parts.count, 25)
        XCTAssertTrue(parts.allSatisfy { $0.count == 201 && $0.first == 0xC7 })
        XCTAssertEqual(parts.reduce(Data()) { $0 + $1.dropFirst() }, data)
        XCTAssertThrowsError(try FrameCodec.encode([]))
        XCTAssertThrowsError(try FrameCodec.packets(Data(repeating: 0, count: 4999)))
    }
    func testMailboxWritableMask() {
        let status = MailboxStatus(raw: 0xF7)
        XCTAssertTrue(status.enabled); XCTAssertTrue(status.rfPending)
        XCTAssertTrue(status.hostPending); XCTAssertTrue(status.missed)
        XCTAssertEqual(MailboxStatus.disable, Data([0x0D, 0]))
        XCTAssertEqual(MailboxStatus.enable, Data([0x0D, 1]))
    }
    func testRasterOrientationMatchesPreview() throws {
        let source = CardRenderer.canvas { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let result = try CardRenderer.render(source, threshold: 120, dither: false)
        var expected = Data(repeating: 255, count: 5000); expected[4975] = 0x7F
        XCTAssertEqual(result.frame, expected, "UIKit→灰度→预览→协议方向必须一致")
    }
    func testGeneratedTestsAndQR() throws {
        XCTAssertEqual(try CardRenderer.render(CardRenderer.test(0), threshold: 120, dither: false).frame, Data(repeating: 0, count: 5000))
        XCTAssertEqual(try CardRenderer.render(CardRenderer.test(1), threshold: 120, dither: false).frame, Data(repeating: 255, count: 5000))
        XCTAssertThrowsError(try CardRenderer.qr(""))
        let image = try CardRenderer.qr("Link-Card")
        XCTAssertEqual(image.size, CGSize(width: 200, height: 200))
    }
}

final class MistBlurStoreTests: XCTestCase {
    private func withDefaults(_ test: (UserDefaults) -> Void) {
        let name = "MistBlurStoreTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        test(defaults)
    }
    func testThreeChannelsMigrationAndRecreation() {
        withDefaults { defaults in
            defaults.set(23.0, forKey: "appearance.blur")
            defaults.set(0.55, forKey: "appearance.veil")
            defaults.set(45.0, forKey: "appearance.cardBlur.global.v1")
            defaults.set(["workbench.base": 62.0, "create.preview": 0.0], forKey: "appearance.cardBlur.overrides.v1")
            let store = MistBlurStore(defaults: defaults)
            XCTAssertEqual(store.global, 45)
            XCTAssertEqual(store.workbench, 62)
            XCTAssertEqual(store.strength(for: "create.preview"), 45)
            store.setGlobal(30); store.setWorkbench(80)
            defaults.set(["workbench.base": 0.0], forKey: "appearance.cardBlur.overrides.v1")
            let restored = MistBlurStore(defaults: defaults)
            XCTAssertEqual(restored.global, 30)
            XCTAssertEqual(restored.workbench, 80)
            XCTAssertEqual(restored.strength(channel: .controls), 30)
            XCTAssertEqual(restored.strength(channel: .workbench), 80)
            XCTAssertEqual(defaults.double(forKey: "appearance.blur"), 23)
            XCTAssertEqual(defaults.double(forKey: "appearance.veil"), 0.55)
        }
    }
    func testArgumentDomainNumericStringsAreNotSilentlyDefaulted() {
        withDefaults { defaults in
            defaults.set(true, forKey: "appearance.blur.migrated.v2")
            for value in ["0", "50", "100"] {
                defaults.set(value, forKey: "appearance.blur.controls.v2")
                defaults.set("0", forKey: "appearance.blur.workbench.v2")
                let store = MistBlurStore(defaults: defaults)
                XCTAssertEqual(store.global, Double(value)!)
                XCTAssertEqual(store.workbench, 0)
            }
            defaults.set("not-a-number", forKey: "appearance.blur.controls.v2")
            XCTAssertEqual(MistBlurStore(defaults: defaults).global, 70)
        }
    }
    func testClampingAndNoPerCardOverride() {
        withDefaults { defaults in
            let store = MistBlurStore(defaults: defaults)
            store.setGlobal(-5); XCTAssertEqual(store.global, 0)
            store.setGlobal(120); XCTAssertEqual(store.global, 100)
            store.setGlobal(.nan); XCTAssertEqual(store.global, 70)
            store.setWorkbench(-1); XCTAssertEqual(store.workbench, 0)
            store.setWorkbench(.infinity); XCTAssertEqual(store.workbench, 70)
            let id = UUID(uuidString: "BEA88787-2B01-452B-9900-7647CD108356")!
            XCTAssertEqual(MistCardTarget.library(id), "library.card.bea88787-2b01-452b-9900-7647cd108356")
            XCTAssertEqual(store.strength(for: MistCardTarget.library(id)), store.global)
        }
    }

}

// UIKit runtime regression candidates; require an iOS test host (not run offline).
final class MistEffectLifecycleTests: XCTestCase {
    @MainActor func testStationaryMaterialAndVisualTintAcrossStrengths() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let view = MistEffectView(effect: nil)
        view.frame = window.bounds
        window.addSubview(view)
        view.setIntensity(50)
        let material = view.effect
        XCTAssertNotNil(material)
        let tint = view.contentView.subviews.first!
        let half = tint.backgroundColor!.cgColor.alpha
        for value in [1.0, 50, 70, 99, 100] {
            view.setIntensity(value)
            XCTAssertTrue(view.effect === material, "Changing visual strength must not rebuild an effect or start an animator")
            XCTAssertEqual(view.alpha, 1)
            XCTAssertEqual(view.superview?.alpha, 1)
            XCTAssertFalse(view.isUserInteractionEnabled)
            XCTAssertTrue((view.layer.animationKeys() ?? []).isEmpty)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertTrue(view.effect === material, "Foreground needs no effect interpolation")
        }
        XCTAssertGreaterThan(tint.backgroundColor!.cgColor.alpha, half)
        view.setIntensity(0)
        XCTAssertNil(view.effect)
        XCTAssertEqual(tint.backgroundColor!.cgColor.alpha, 0)
        view.removeFromSuperview()
    }
    @MainActor func testUnchangedIntensityAndLayoutDoNotRebuild() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let view = MistEffectView(effect: nil)
        window.addSubview(view)
        for value in [70.0, 100.0, 0.0] {
            view.setIntensity(value)
            let before = view.rebuildCount
            for _ in 0..<200 {
                view.setIntensity(value)
                view.setNeedsLayout(); view.layoutIfNeeded()
            }
            XCTAssertEqual(view.rebuildCount, before, "Unchanged strength/layout must not rebuild")
            print("PERF unchanged-intensity=\(value) updates=200 rebuilds=\(view.rebuildCount - before)")
        }
        view.removeFromSuperview()
    }
    @MainActor func testEndpointsDetachReattachAndRepeatedStop() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let view = MistEffectView(effect: nil)
        window.addSubview(view)
        for _ in 0..<100 {
            for value in [0.0, 1, 50, 99, 100, 70, 0] {
                view.setIntensity(value)
                if value == 0 { XCTAssertNil(view.effect) }
            }
            view.setIntensity(100)
            XCTAssertNotNil(view.effect)
            view.removeFromSuperview()
            XCTAssertNil(view.effect)
            window.addSubview(view)
            XCTAssertNotNil(view.effect)
            view.stopEffect()
            view.stopEffect()
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertNil(view.effect, "Dismantled effect must not reactivate")
        }
        view.removeFromSuperview()
    }

    @MainActor func testTraitChangesAndForegroundWithPartialIntensity() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let parent = UIViewController()
        let child = UIViewController()
        window.rootViewController = parent
        parent.addChild(child)
        parent.view.addSubview(child.view)
        child.didMove(toParent: parent)
        let effect = MistEffectView(effect: nil)
        child.view.addSubview(effect)
        // A rootViewController assignment alone does not attach its view to a
        // hidden UIWindow. Production intentionally defers effects off-window.
        print("Mist fixture before mounting: effect.window is nil = \(effect.window == nil)")
        window.makeKeyAndVisible()
        parent.view.frame = window.bounds
        child.view.frame = parent.view.bounds
        effect.frame = child.view.bounds
        window.layoutIfNeeded()
        XCTAssertTrue(effect.window === window, "Trait test must exercise an attached effect")
        XCTAssertFalse(effect.bounds.isEmpty)
        defer {
            effect.stopEffect()
            effect.removeFromSuperview()
            window.isHidden = true
            window.rootViewController = nil
        }
        for _ in 0..<100 {
            for contrast in [UIAccessibilityContrast.high, .normal] {
                for style in [UIUserInterfaceStyle.dark, .light] {
                    effect.setIntensity(70)
                    parent.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
                        UITraitCollection(accessibilityContrast: contrast),
                        UITraitCollection(userInterfaceStyle: style)
                    ]), forChild: child)
                    child.view.layoutIfNeeded()
                    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
                    effect.setIntensity(0)
                    XCTAssertNil(effect.effect)
                    effect.setIntensity(100)
                    XCTAssertNotNil(effect.effect)
                }
            }
        }
    }

    @MainActor func testNonFiniteInputsAndRelease() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        weak var released: MistEffectView?
        autoreleasepool {
            let view = MistEffectView(effect: nil)
            released = view
            window.addSubview(view)
            for value in [Double.nan, Double.infinity, -Double.infinity, -1, 101, 70] {
                view.setIntensity(value)
            }
            view.stopEffect()
            view.removeFromSuperview()
        }
        XCTAssertNil(released)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    }
}

// No radio access: exercise the real dismissal methods on a fresh coordinator.
final class BLEConnectionPresentationTests: XCTestCase {
    @MainActor func testInteractiveDismissCancelsCurrentDiscovery() {
        let ble = PCRBluetooth()
        let trusted = ble.preferences.trusted.map { $0.id }
        ble.connectionPromptDidDisappear()
        XCTAssertEqual(ble.status, "已取消本次自动发现；点击扫描可重新开始。")
        XCTAssertFalse(ble.scanning)
        XCTAssertEqual(ble.preferences.trusted.map { $0.id }, trusted)
    }

    @MainActor func testHidePromptDoesNotCancelOrRevokeTrust() {
        let ble = PCRBluetooth()
        let oldPrompt = ble.preferences.showDiscoveryPrompt
        let oldAuto = ble.preferences.autoScan
        let trusted = ble.preferences.trusted.map { $0.id }
        let status = ble.status
        defer { ble.setDiscoveryPrompt(oldPrompt) }
        ble.setDiscoveryPrompt(false)
        ble.connectionPromptDidDisappear()
        XCTAssertEqual(ble.status, status, "Programmatic hide must not invoke cancellation")
        XCTAssertEqual(ble.preferences.autoScan, oldAuto)
        XCTAssertEqual(ble.preferences.trusted.map { $0.id }, trusted)
        XCTAssertFalse(ble.preferences.showDiscoveryPrompt)
    }

    @MainActor func testBackgroundProgrammaticDismissDoesNotBecomeUserCancel() {
        let ble = PCRBluetooth()
        let oldAuto = ble.preferences.autoScan
        ble.setAutomaticScanning(false)
        defer { ble.setAutomaticScanning(oldAuto) }
        ble.setForeground(true)
        ble.setForeground(false)
        let status = ble.status
        ble.connectionPromptDidDisappear()
        XCTAssertEqual(ble.status, status)
        XCTAssertFalse(ble.active)
        XCTAssertFalse(ble.scanning)
    }
}

final class WorkbenchPresentationTests: XCTestCase {
    @MainActor func testProductionStowRestoreAndAdaptiveBounds() {
        XCTAssertEqual(WorkbenchState.availableHeight(proposed: 655, top: 100, bottomInset: 0, tabTop: 694), 594)
        XCTAssertEqual(WorkbenchState.availableHeight(proposed: 300, top: 100, bottomInset: 34, tabTop: 500), 266)
        XCTAssertEqual(WorkbenchState.availableHeight(proposed: 180, top: 100, bottomInset: 0, tabTop: nil), 180)
        XCTAssertEqual(WorkbenchState.availableHeight(proposed: 100, top: 500, bottomInset: 34, tabTop: 400), 0)
        let state = WorkbenchState()
        for expanded in [false, true] {
            state.expanded = expanded
            state.stow()
            XCTAssertFalse(state.stowed, "Legacy stow must remain reachable as compact")
            for tab in MainTab.allCases { state.tab = tab }
            state.tab = .create
            state.restore()
            XCTAssertFalse(state.stowed)
            XCTAssertFalse(state.expanded)
        }
        for width in [CGFloat(320), 375, 390, 768] {
            let side = WorkbenchState.previewSide(width: width)
            XCTAssertLessThanOrEqual(side, 230)
            XCTAssertLessThanOrEqual(side + 20, width * 0.68)
        }
        for height in [CGFloat(180), 360, 600] {
            for expanded in [false, true] {
                for accessibility in [false, true] {
                    for keyboard in [false, true] {
                        let actual = WorkbenchState.height(available: height, expanded: expanded, accessibility: accessibility, keyboard: keyboard)
                        XCTAssertGreaterThan(actual, 0)
                        XCTAssertLessThanOrEqual(actual, height)
                    }
                }
            }
        }
    }

    @MainActor func testProductionNavigationEnvironmentAndSnapshots() throws {
        let state = WorkbenchState()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: ContentView(workbench: state))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("workbench-snapshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func settleAndCapture(_ name: String) throws {
            RunLoop.main.run(until: Date().addingTimeInterval(0.7))
            host.view.frame = window.bounds
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            XCTAssertFalse(host.view.bounds.isEmpty)
            XCTAssertTrue(host.view.window === window)
            XCTAssertNotNil(window.windowScene)
            if state.tab == .create && !state.stowed {
                // Non-throwing checks let PNG export continue even when geometry is missing.
                XCTAssertNotNil(state.frames["panel"], "Actual workbench frame missing")
                XCTAssertNotNil(state.frames["tabs"], "Actual tab height missing")
                if let panel = state.frames["panel"], let tabs = state.frames["tabs"] {
                    XCTAssertGreaterThan(panel.height, 0)
                    XCTAssertGreaterThan(tabs.height, 44)
                    XCTAssertLessThanOrEqual(panel.maxY, tabs.minY + 1, "Tab bar must not cover editor")
                    print("LAYOUT \(name) panel=\(panel) tabs=\(tabs)")
                }
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertGreaterThan(Set(pixels).count, 32, "Reject blank/off-scene screenshots")
            let data = try XCTUnwrap(image.pngData())
            try data.write(to: folder.appendingPathComponent(name + ".png"))
            let attachment = XCTAttachment(image: image)
            attachment.name = name; attachment.lifetime = .keepAlways
            add(attachment)
        }
        try settleAndCapture("01-compact")
        state.expanded = true
        try settleAndCapture("02-expanded")
        let initialRenders = state.renderCount
        // Regression coverage: switch to Settings WITHOUT stowing the workbench.
        for expanded in [false, true] {
            state.expanded = expanded
            for _ in 0..<8 {
                state.tab = .settings
                RunLoop.main.run(until: Date().addingTimeInterval(0.12))
                host.view.layoutIfNeeded()
                state.tab = .create
                RunLoop.main.run(until: Date().addingTimeInterval(0.12))
                host.view.layoutIfNeeded()
            }
        }
        XCTAssertEqual(state.renderCount, initialRenders, "Tab changes must not rerender card pixels")
        print("PERF open-workbench-settings roundtrips=16 extra-card-renders=\(state.renderCount - initialRenders)")
        state.tab = .settings
        try settleAndCapture("02b-settings-from-open")
        state.tab = .create
        state.expanded = true
        state.stow()
        try settleAndCapture("03-stowed")
        for tab in [MainTab.settings, .library, .device, .create] {
            state.tab = tab
            try settleAndCapture("04-tab-\(tab.rawValue)")
        }
        state.restore()
        XCTAssertFalse(state.expanded, "Legacy restore remains compact and reachable")
        state.expanded = true
        try settleAndCapture("05-restored-expanded")
        host.rootView = ContentView(workbench: state)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        try settleAndCapture("06-small-expanded")
        let accessible = UIHostingController(rootView: ContentView(workbench: state).environment(\.dynamicTypeSize, .accessibility3))
        window.rootViewController = accessible
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        accessible.view.layoutIfNeeded()
        XCTAssertFalse(accessible.view.bounds.isEmpty)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("07-accessibility.png"))
        let panel = try XCTUnwrap(state.frames["panel"], "Accessibility panel missing")
        let tabs = try XCTUnwrap(state.frames["tabs"], "Accessibility tabs missing")
        XCTAssertGreaterThan(panel.height, 0)
        XCTAssertGreaterThan(tabs.height, 44)
        XCTAssertLessThanOrEqual(panel.maxY, tabs.minY + 1, "Tab bar must not cover accessibility editor")
        print("LAYOUT 07-accessibility panel=\(panel) tabs=\(tabs)")
    }
}

/// Runs production state/Shape and hosts the actual SwiftUI root in a simulator.
/// These are real hierarchy captures, not HTML renders or touch-driven XCUITest.
final class FusionPresentationTests: XCTestCase {
    @MainActor func testProductionConfigurationDedupAndLatestAction() {
        var tapped = 0
        let button = UIButton(type: .system)
        let coordinator = FusionButton.Coordinator({ tapped = -1 })
        button.addTarget(coordinator, action: #selector(FusionButton.Coordinator.tap), for: .touchUpInside)
        for index in 0..<200 {
            FusionButton(title: "设置", symbol: "gearshape", id: "test.config", action: { tapped = index })
                .configure(button, coordinator: coordinator, pointSize: 17)
        }
        XCTAssertEqual(coordinator.configurationCommitCount, 1)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(tapped, 199)
        FusionButton(title: "新设置", symbol: "gearshape", id: "test.config", action: {})
            .configure(button, coordinator: coordinator, pointSize: 17)
        XCTAssertEqual(coordinator.configurationCommitCount, 2)
        FusionButton(title: "新设置", symbol: "gearshape", id: "test.config", selected: true, action: {})
            .configure(button, coordinator: coordinator, pointSize: 20)
        XCTAssertEqual(coordinator.configurationCommitCount, 3)
        print("CONFIGURATION 200 identical updates = 1 commit; latest action=199; changed visuals reinstall")
    }
    @MainActor func testDisplayLinkStopsOnInactiveAndBackgroundWithoutDisappear() {
        let progress = FusionProgress()
        progress.setSceneActive(true)
        progress.move(to: 2)
        XCTAssertTrue(progress.isRunning)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertFalse(progress.isRunning)
        let before = progress.tickCount
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        progress.move(to: 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(progress.tickCount - before, 0)
        XCTAssertEqual(progress.value, 1)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(progress.isRunning)
        XCTAssertEqual(progress.value, 1)
        weak var released: FusionProgress?
        autoreleasepool {
            let temporary = FusionProgress(); released = temporary
            temporary.setSceneActive(true); temporary.move(to: 2)
        }
        XCTAssertNil(released, "Display target must not retain its owner")
        print("BACKGROUND display callbacks=0; foreground final intent restored; owner released")
    }
    @MainActor func testProductionDrawerGeometryAndDragReversal() {
        for width in [CGFloat(320), 360, 390, 430, 768] {
            let drawer = FusionState.drawerWidth(width)
            XCTAssertEqual(drawer, min(280, width * 0.65))
            XCTAssertLessThanOrEqual(drawer, width)
            let state = FusionState()
            state.drawer = drawer * 0.4
            state.drag(translation: 24, predicted: 40, width: drawer, y: 300)
            XCTAssertEqual(state.drawer, drawer * 0.4 + 24, accuracy: 0.01)
            XCTAssertGreaterThan(state.bend, 0)
            state.drag(translation: -32, predicted: -80, width: drawer, y: 310)
            XCTAssertEqual(state.drawer, drawer * 0.4 - 32, accuracy: 0.01)
            XCTAssertLessThan(state.bend, 0)
            state.finish(predictedDelta: -90, width: drawer)
            XCTAssertEqual(state.drawer, 0); XCTAssertEqual(state.bend, 0); XCTAssertNil(state.dragOrigin)
            let shape = FusionDrawerShape(bend: 0, touchY: 300).path(in: CGRect(x: 0, y: 0, width: drawer, height: 700))
            XCTAssertEqual(shape.boundingRect.width, drawer, accuracy: 0.01)
            XCTAssertFalse(shape.contains(CGPoint(x: drawer - 1, y: 300)), "Rest edge has a broad inward curve")
            XCTAssertTrue(shape.contains(CGPoint(x: drawer - 20, y: 300)))
        }
    }
    @MainActor func testContinuousProductionGeometryAndNotch() {
        for size in [CGSize(width: 320, height: 440), CGSize(width: 390, height: 750), CGSize(width: 430, height: 820)] {
            for step in 0...100 {
                let g = FusionWorkbenchGeometry(size: size, progress: 1 + CGFloat(step) / 100)
                XCTAssertEqual(g.panel.minX, 0)
                XCTAssertEqual(g.panel.width, size.width)
                XCTAssertEqual(g.panel.maxY, size.height, accuracy: 0.01)
                XCTAssertEqual(g.avatar.midY, g.panel.minY, accuracy: 0.01)
                XCTAssertGreaterThanOrEqual(g.handle.width, 44)
                XCTAssertGreaterThanOrEqual(g.handle.height, 44)
                XCTAssertFalse(g.avatar.intersects(g.handle))
                XCTAssertLessThanOrEqual(g.header.maxY, g.content.minY)
                XCTAssertLessThanOrEqual(g.content.maxY, g.tabs.minY + 0.01)
                XCTAssertLessThanOrEqual(g.tabs.maxY, size.height)
                XCTAssertGreaterThan(g.content.height, 0)
            }
            let width = FusionState.drawerWidth(size.width)
            let state = FusionState()
            state.drag(translation: 70, predicted: 70, width: width, y: 240)
            XCTAssertGreaterThan(state.bend, 0, "Slow drag must bend without prediction")
            let shape = FusionDrawerShape(bend: state.bend, touchY: 240, trailingSpace: 40)
                .path(in: CGRect(x: 0, y: 0, width: width + 40, height: size.height))
            XCTAssertTrue(shape.contains(CGPoint(x: width - 2, y: 240)), "Slow drag changes the actual curved boundary")
            XCTAssertGreaterThanOrEqual(shape.boundingRect.maxX, width)
            XCTAssertLessThanOrEqual(shape.boundingRect.maxX, width + 40)
        }
        let notch = FusionNotch().path(in: CGRect(x: 0, y: 0, width: 320, height: 300))
        XCTAssertFalse(notch.contains(CGPoint(x: 160, y: 12), eoFill: true))
        XCTAssertTrue(notch.contains(CGPoint(x: 160, y: 40), eoFill: true))
        XCTAssertTrue(notch.contains(CGPoint(x: 80, y: 12), eoFill: true))
    }
    @MainActor func testFusionNativeScreensAndSmallSafeGeometry() throws {
        let workbench = WorkbenchState(); let fusion = FusionState()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: AnyView(ContentView(workbench: workbench, fusion: fusion).environment(\.scenePhase, .active)))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("workbench-snapshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func capture(_ name: String) throws {
            RunLoop.main.run(until: Date().addingTimeInterval(0.65))
            host.view.frame = window.bounds; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            let toolbar = try XCTUnwrap(workbench.frames["fusion.toolbar"])
            XCTAssertNil(workbench.frames["fusion.modes"], "Removed mode switch must not reserve layout")
            let panel = try XCTUnwrap(workbench.frames["panel"])
            let tabs = try XCTUnwrap(workbench.frames["tabs"])
            let avatar = try XCTUnwrap(workbench.frames["avatar"])
            let handle = try XCTUnwrap(workbench.frames["handle"])
            XCTAssertFalse(avatar.intersects(handle), "Avatar must never cover the handle")
            XCTAssertEqual(avatar.width, avatar.height, accuracy: 0.1)
            XCTAssertLessThanOrEqual(toolbar.maxY, avatar.minY, "Floating header must not overlap the avatar")
            XCTAssertGreaterThanOrEqual(handle.width, 44)
            XCTAssertGreaterThanOrEqual(handle.height, 44)
            XCTAssertLessThanOrEqual(panel.maxY, tabs.minY + 1)
            XCTAssertGreaterThan(panel.height, 0)
            if workbench.tab == .create {
                for key in ["create.column", "create.preview.row", "create.caption"] {
                    let frame = try XCTUnwrap(workbench.frames[key])
                    XCTAssertGreaterThanOrEqual(frame.minX, panel.minX - 1, "\(name): \(key) spills left")
                    XCTAssertLessThanOrEqual(frame.maxX, panel.maxX + 1, "\(name): \(key) spills right")
                    XCTAssertEqual(frame.midX, panel.midX, accuracy: 1, "\(name): readable column must remain centered")
                    print("CREATE-CONTENT \(name) \(key)=\(frame)")
                }
            }
            XCTAssertGreaterThanOrEqual(tabs.height, 44)
            XCTAssertGreaterThanOrEqual(tabs.minX, 0)
            XCTAssertLessThanOrEqual(tabs.maxX, window.bounds.width + 1)
            XCTAssertLessThanOrEqual(tabs.maxY, window.bounds.height - window.safeAreaInsets.bottom + 1)
            // SwiftUI tab labels are not UILabels: production GeometryReader probes
            // measure the actual image/text layout before the outer clipping boundary.
            for tab in [MainTab.create, .device, .library] {
                let prefix = "tab.\(tab.rawValue)"
                let buttonFrame = try XCTUnwrap(workbench.frames[prefix + ".button"])
                let iconFrame = try XCTUnwrap(workbench.frames[prefix + ".icon"])
                let titleFrame = try XCTUnwrap(workbench.frames[prefix + ".title"])
                XCTAssertTrue(tabs.insetBy(dx: -1, dy: -1).contains(buttonFrame), "\(name): tab exceeds allocated bar \(tab)")
                for frame in [iconFrame, titleFrame] {
                    XCTAssertFalse(frame.isEmpty, "\(name): missing tab content \(tab)")
                    XCTAssertTrue(buttonFrame.insetBy(dx: -1, dy: -1).contains(frame), "\(name): clipped tab content \(tab) \(frame) outside \(buttonFrame)")
                }
                XCTAssertFalse(iconFrame.insetBy(dx: 1, dy: 1).intersects(titleFrame), "\(name): tab title overlaps symbol \(tab)")
                XCTAssertLessThanOrEqual(iconFrame.height, 32, "\(name): oversized tab symbol \(tab)")
                print("TAB-CONTENT \(name) \(tab) button=\(buttonFrame) icon=\(iconFrame) title=\(titleFrame)")
            }
            // Validate rendered UIKit contents, not just the representable's outer frame.
            for id in ["fusion.menu", "fusion.settings"] {
                let button = try XCTUnwrap(findButton(window, id), "Missing production button \(id)")
                button.layoutIfNeeded()
                let allowed = button.bounds.insetBy(dx: -1, dy: -1)
                if let image = button.imageView, image.image != nil {
                    let frame = image.convert(image.bounds, to: button)
                    XCTAssertFalse(frame.isEmpty, "\(name): empty symbol \(id)")
                    XCTAssertTrue(allowed.contains(frame), "\(name): symbol \(id) \(frame) exceeds \(button.bounds)")
                    XCTAssertLessThanOrEqual(frame.width, 32, "\(name): SF Symbol inflated \(id)")
                    XCTAssertLessThanOrEqual(frame.height, 32, "\(name): SF Symbol inflated \(id)")
                }
                if id == "fusion.menu" { continue } // Icon-only, full 44pt target.
                let label = try XCTUnwrap(button.titleLabel, "Missing title label \(id)")
                let frame = label.convert(label.bounds, to: button)
                XCTAssertFalse(frame.isEmpty, "\(name): empty title \(id)")
                XCTAssertTrue(allowed.contains(frame), "\(name): title \(id) \(frame) exceeds \(button.bounds)")
                let fitted = label.sizeThatFits(CGSize(width: frame.width, height: .greatestFiniteMagnitude))
                XCTAssertLessThanOrEqual(fitted.height, frame.height + 1, "\(name): truncated title height \(id)")
                XCTAssertLessThanOrEqual(fitted.width, frame.width + 1, "\(name): truncated title width \(id)")
                if let image = button.imageView, image.image != nil {
                    XCTAssertFalse(frame.insetBy(dx: 1, dy: 1).intersects(image.convert(image.bounds, to: button)), "\(name): overlapping title and symbol \(id)")
                }
                print("BUTTON-CONTENT \(name) \(id) button=\(button.bounds) image=\(String(describing: button.imageView?.frame)) title=\(frame)")
            }
            print("FUSION \(name) toolbar=\(toolbar) panel=\(panel) tabs=\(tabs) safe=\(window.safeAreaInsets)")
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertGreaterThan(Set(pixels).count, 32)
            try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent(name + ".png"))
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        func findButton(_ view: UIView, _ id: String) -> UIButton? {
            if let b = view as? UIButton, b.accessibilityIdentifier == id { return b }
            for child in view.subviews { if let b = findButton(child, id) { return b } }
            return nil
        }
        func tap(_ id: String) throws {
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            window.layoutIfNeeded()
            let button = try XCTUnwrap(findButton(window, id), "Missing production button \(id)")
            let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
            let hit = try XCTUnwrap(window.hitTest(center, with: nil), "No hit at \(center)")
            XCTAssertTrue(hit === button || hit.isDescendant(of: button), "Transparent overlay intercepted \(id): \(hit)")
            guard hit === button || hit.isDescendant(of: button) else { return }
            button.sendActions(for: .touchUpInside)
            RunLoop.main.run(until: Date().addingTimeInterval(0.75))
            print("HITTEST production UIControl \(id) center=\(center) -> \(hit)")
        }
        try capture("fusion-01-home")
        XCTAssertFalse(workbench.expanded)
        try tap("workbench.handle"); XCTAssertTrue(workbench.expanded)
        try capture("fusion-02-expanded")
        try tap("fusion.menu"); XCTAssertTrue(fusion.drawerOwner?.targetOpen == true)
        try capture("fusion-03-sidebar")
        try tap("fusion.close"); XCTAssertTrue(fusion.drawerOwner?.targetOpen == false)
        try capture("fusion-04-expanded")
        try tap("fusion.settings"); XCTAssertEqual(workbench.tab, .settings)
        try capture("fusion-05-settings")
        try tap("workbench.handle"); XCTAssertFalse(workbench.expanded, "Settings must not force open")
        try capture("fusion-05b-settings-compact")
        try tap("workbench.handle"); XCTAssertTrue(workbench.expanded)
        workbench.tab = .create
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        try capture("fusion-06-small-expanded")
        try tap("workbench.handle"); XCTAssertFalse(workbench.expanded)
        try capture("fusion-07-small-home")
        host.rootView = AnyView(ContentView(workbench: workbench, fusion: fusion).environment(\.dynamicTypeSize, .accessibility5).environment(\.scenePhase, .active))
        try tap("workbench.handle"); XCTAssertTrue(workbench.expanded)
        try capture("fusion-09-small-accessibility")
        try tap("workbench.handle"); XCTAssertFalse(workbench.expanded, "Accessibility size must not force open")
        try capture("fusion-10-accessibility-compact")
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        try capture("fusion-11-390-accessibility-compact")
        try tap("workbench.handle"); XCTAssertTrue(workbench.expanded)
        try capture("fusion-12-390-accessibility-expanded")
        for _ in 0..<5 {
            try tap("workbench.handle"); XCTAssertFalse(workbench.expanded)
            try tap("workbench.handle"); XCTAssertTrue(workbench.expanded)
            try tap("fusion.menu"); XCTAssertTrue(fusion.drawerOwner?.targetOpen == true)
            try tap("fusion.close"); XCTAssertTrue(fusion.drawerOwner?.targetOpen == false)
            try tap("fusion.settings"); XCTAssertEqual(workbench.tab, .settings)
            workbench.tab = .create
        }
        print("REPEAT 5 workbench/sidebar/settings cycles; host cleanup follows")

    }
}

// These tests drive the production recognizer target, UIKit hitTest tree and real
// CADisplayLink. The recognizer input is injected; it is not a physical touch/FPS claim.
private final class DrawerInputPan: UIPanGestureRecognizer {
    var inputState: UIGestureRecognizer.State = .possible
    var inputPoint = CGPoint(x: 8, y: 320)
    var inputX: CGFloat = 0
    var inputVelocity: CGFloat = 200
    var fingers = 1
    override var state: UIGestureRecognizer.State { get { inputState } set { inputState = newValue } }
    override var numberOfTouches: Int { fingers }
    override func translation(in view: UIView?) -> CGPoint { CGPoint(x: inputX, y: 0) }
    override func location(in view: UIView?) -> CGPoint { inputPoint }
    override func velocity(in view: UIView?) -> CGPoint { CGPoint(x: inputVelocity, y: 0) }
}

extension FusionPresentationTests {
    @MainActor func testNativeDrawerThreeStagesReversalAndRealFrameIsolation() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let fusion = FusionState(), workbench = WorkbenchState()
        let host = UIHostingController(rootView: ContentView(workbench: workbench, fusion: fusion).environment(\.scenePhase, .active))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { fusion.drawerOwner?.shutdown(); window.isHidden = true; window.rootViewController = nil }
        func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        wait(0.8); host.view.layoutIfNeeded()
        let owner = try XCTUnwrap(fusion.drawerOwner)
        XCTAssertTrue(owner.sceneActive, "Production bridge must receive the active host scene")
        let w = owner.width; XCTAssertEqual(w, min(280, owner.view.bounds.width * 0.65), accuracy: 0.01)
        let pan = DrawerInputPan()
        func input(_ state: UIGestureRecognizer.State, _ x: CGFloat, y: CGFloat = 320) {
            pan.inputState = state; pan.inputX = x; pan.inputPoint = CGPoint(x: 8 + x, y: y)
            owner.handlePan(pan)
        }
        func capture(_ name: String) throws {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("workbench-snapshots")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            try XCTUnwrap(image.pngData()).write(to: dir.appendingPathComponent(name + ".png"))
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        input(.began, 0); input(.changed, w * 0.49)
        XCTAssertEqual(owner.q, w * 0.49, accuracy: 0.01); XCTAssertEqual(owner.phase, .manual)
        try capture("fluid-01-manual-49")
        input(.ended, w * 0.49); wait(0.7)
        XCTAssertEqual(owner.phase, .closed); XCTAssertEqual(owner.q, 0)
        // Touch y uses the full drawer coordinate space, including top and bottom.
        for y in [CGFloat(70), owner.view.bounds.height / 2, owner.view.bounds.height - 70] {
            input(.began, 0, y: y); input(.changed, w * 0.4, y: y)
            XCTAssertEqual(owner.outline[4].y, y, accuracy: 0.01)
            XCTAssertEqual(owner.outline[4].x + owner.q - w, owner.q, accuracy: 0.01)
            input(.cancelled, w * 0.4, y: y); wait(0.7)
        }
        input(.began, 0); input(.changed, w * 0.51)
        XCTAssertEqual(owner.phase, .position); XCTAssertTrue(owner.targetOpen)
        wait(0.05)
        XCTAssertEqual(owner.phase, .position)
        try capture("fluid-02-auto")
        input(.ended, w * 0.51)
        XCTAssertTrue(owner.targetOpen, "UP after automatic takeover must be consumed")
        let rootCount = fusion.rootBodyCount, configs = FusionButton.Coordinator.totalConfigurationCommits
        let rebuilds = owner.blur.rebuildCount, menuUpdates = owner.menuUpdateCount, frames = owner.frameCount
        let deadline = Date().addingTimeInterval(1)
        while owner.phase == .position && Date() < deadline { wait(0.005) }
        XCTAssertEqual(owner.phase, .shape); XCTAssertEqual(owner.q, w, accuracy: 0.01)
        let initialShape = owner.outline
        wait(0.14)
        XCTAssertEqual(owner.phase, .shape); XCTAssertEqual(owner.q, w, accuracy: 0.01)
        XCTAssertNotEqual(owner.outline, initialShape)
        XCTAssertLessThan(owner.outline[4].x, w, "Shape has a real reverse overshoot peak")
        try capture("fluid-03-return-peak")
        wait(0.2); XCTAssertEqual(owner.phase, .open); XCTAssertFalse(owner.isRunning)
        XCTAssertGreaterThan(owner.frameCount - frames, 3)
        XCTAssertEqual(owner.blur.rebuildCount, rebuilds)
        XCTAssertEqual(owner.menuUpdateCount, menuUpdates)
        XCTAssertEqual(FusionButton.Coordinator.totalConfigurationCommits, configs)
        XCTAssertEqual(fusion.rootBodyCount, rootCount)
        print("DRAWER actual frames=\(owner.frameCount-frames) blur rebuild delta=\(owner.blur.rebuildCount-rebuilds) menu update delta=\(owner.menuUpdateCount-menuUpdates) root body delta=\(fusion.rootBodyCount-rootCount) button config delta=\(FusionButton.Coordinator.totalConfigurationCommits-configs)")
        try capture("fluid-04-open")
        owner.request(open: false); wait(0.06)
        let actualQ = owner.q, actualShape = owner.outline, oldGeneration = owner.generation
        input(.began, 0)
        XCTAssertEqual(owner.q, actualQ); XCTAssertEqual(owner.outline, actualShape)
        owner.advance(CACurrentMediaTime() + 4, generation: oldGeneration)
        XCTAssertEqual(owner.q, actualQ, "Cancelled callbacks cannot overwrite a new gesture")
        input(.changed, 8)
        XCTAssertEqual(owner.q, min(w, actualQ + 8), accuracy: 0.01)
        pan.fingers = 2; input(.changed, 80)
        XCTAssertEqual(owner.q, min(w, actualQ + 8), accuracy: 0.01)
        input(.cancelled, 80)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertFalse(owner.isRunning)
        let stopped = owner.frameCount; owner.request(open: true); wait(0.08)
        XCTAssertEqual(owner.frameCount, stopped)
        owner.setActive(true); XCTAssertFalse(owner.isRunning)
        // Real hierarchy: outside the visible drawer is not swallowed by the overlay.
        let outside = CGPoint(x: owner.view.bounds.maxX - 2, y: 400)
        XCTAssertNil(owner.view.hitTest(outside, with: nil))
    }

    @MainActor func testNativeDrawerOwnerReleaseAndRotation() {
        weak var weakOwner: DrawerRenderOwner?
        autoreleasepool {
            let owner = DrawerRenderOwner(); weakOwner = owner
            owner.loadViewIfNeeded(); owner.view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
            owner.viewDidLayoutSubviews(); owner.request(open: true)
            XCTAssertTrue(owner.isRunning)
            owner.view.frame.size = CGSize(width: 600, height: 390); owner.viewDidLayoutSubviews()
            XCTAssertFalse(owner.isRunning); XCTAssertEqual(owner.q, 280)
            owner.request(open: false); XCTAssertTrue(owner.isRunning)
        }
        XCTAssertNil(weakOwner, "Display link and notification callbacks must not retain production owner")
    }
}

extension FusionPresentationTests {
    @MainActor func testPreviewSceneGateDirtyResumeOnly() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene), workbench = WorkbenchState(), fusion = FusionState()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: ContentView(workbench: workbench, fusion: fusion).environment(\.scenePhase, .inactive))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(workbench.renderCount, 0, "Non-active scene must not enter the synchronous renderer")
        host.rootView = ContentView(workbench: workbench, fusion: fusion).environment(\.scenePhase, .active)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        host.rootView = ContentView(workbench: workbench, fusion: fusion).environment(\.scenePhase, .inactive)
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        XCTAssertEqual(workbench.renderCount, 0, "Waiting preview is cancelled on inactive")
        host.rootView = ContentView(workbench: workbench, fusion: fusion).environment(\.scenePhase, .active)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(workbench.renderCount, 1, "Dirty preview resumes once")
        host.rootView = ContentView(workbench: workbench, fusion: fusion).environment(\.scenePhase, .background)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.rootView = ContentView(workbench: workbench, fusion: fusion).environment(\.scenePhase, .active)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(workbench.renderCount, 1, "Clean preview is not rerendered on activation")
    }
}

// Run on iOS 16.6: these use UIWindow hit testing, not an accessibility-only tap.
extension FusionPresentationTests {
    @MainActor func testDrawerPortalWindowHitsMasksAndSingleActions() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let fusion = FusionState(), workbench = WorkbenchState()
        let host = UIHostingController(rootView: ContentView(workbench: workbench, fusion: fusion).environment(\.scenePhase, .active))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { fusion.drawerOwner?.shutdown(); window.isHidden = true; window.rootViewController = nil }
        func wait(_ seconds: Double = 0.1) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)); window.layoutIfNeeded() }
        wait(0.8)
        let owner = try XCTUnwrap(fusion.drawerOwner)
        XCTAssertTrue(owner.parent === host)
        XCTAssertTrue(owner.view.superview === host.view)
        XCTAssertEqual(owner.view.convert(owner.view.bounds, to: window), window.bounds)
        XCTAssertNil(owner.surface.layer.mask, "An effect ancestor must not be masked")
        XCTAssertNotNil(owner.blur.mask)
        XCTAssertEqual(owner.blur.alpha, 1)
        XCTAssertEqual(owner.surface.alpha, 1)
        XCTAssertFalse(owner.pan.cancelsTouchesInView)
        XCTAssertTrue(owner.pan.view === host.view)
        if #available(iOS 16.4, *) { XCTAssertEqual(owner.menu.safeAreaRegions, .keyboard) }
        XCTAssertGreaterThanOrEqual(owner.menu.view.frame.minY, window.safeAreaInsets.top)
        XCTAssertLessThanOrEqual(owner.menu.view.frame.maxY, window.bounds.height - window.safeAreaInsets.bottom)
        func findButton(_ view: UIView, _ id: String) -> UIButton? {
            if let b = view as? UIButton, b.accessibilityIdentifier == id { return b }
            for child in view.subviews { if let b = findButton(child, id) { return b } }
            return nil
        }
        func tap(_ id: String, startsDrawerRequest: Bool = false) throws {
            let button = try XCTUnwrap(findButton(window, id))
            let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
            let hit = try XCTUnwrap(window.hitTest(point, with: nil))
            XCTAssertTrue(hit === button || hit.isDescendant(of: button), "Hit intercepted: \(id): \(hit)")
            guard hit === button || hit.isDescendant(of: button) else { return }
            var actionCount = 0
            let observer = UIAction { _ in actionCount += 1 }
            button.addAction(observer, for: .touchUpInside)
            let generation = owner.generation
            button.sendActions(for: .touchUpInside)
            button.removeAction(observer, for: .touchUpInside)
            XCTAssertEqual(actionCount, 1)
            if startsDrawerRequest { XCTAssertEqual(owner.generation, generation + 1, "Production request must execute once") }
        }
        // Includes the old edge strip, not merely a far-right sample.
        for x in [CGFloat(1), 12, 23, 180, 389] {
            for y in [CGFloat(1), 120, 400, 843] {
                XCTAssertNil(owner.view.hitTest(CGPoint(x: x, y: y), with: nil))
            }
        }
        XCTAssertFalse(owner.view.accessibilityViewIsModal, "Closed drawer must not hide main content from AX")
        try tap("workbench.handle"); XCTAssertTrue(workbench.expanded); wait(0.6)
        try tap("fusion.menu", startsDrawerRequest: true); wait(0.95)
        XCTAssertEqual(owner.phase, .open)
        XCTAssertTrue(owner.view.accessibilityViewIsModal, "Open drawer must isolate overlapping SwiftUI AX siblings")
        try tap("fusion.close", startsDrawerRequest: true); wait(0.75)
        XCTAssertEqual(owner.phase, .closed)
        XCTAssertFalse(owner.view.accessibilityViewIsModal, "Closing restores the main content AX graph")
        try tap("fusion.settings"); XCTAssertEqual(workbench.tab, .settings); wait()
        // Drive production pan target. This is not an injected physical UITouch.
        let pan = DrawerInputPan()
        pan.inputState = .began; owner.handlePan(pan)
        pan.inputState = .changed; pan.inputX = owner.width * 0.4; owner.handlePan(pan)
        func checkVisiblePathHits() {
            let path = owner.maskLayer.path!
            for y in stride(from: CGFloat(2), to: owner.view.bounds.height, by: 37) {
                for x in stride(from: CGFloat(2), to: owner.view.bounds.width, by: 17) {
                    let point = CGPoint(x: x, y: y)
                    let inside = path.contains(owner.surface.convert(point, from: owner.view))
                    XCTAssertEqual(owner.view.hitTest(point, with: nil) != nil, inside)
                    let actual = window.hitTest(owner.view.convert(point, to: window), with: nil)
                    if let actual {
                        XCTAssertEqual(actual === owner.view || actual.isDescendant(of: owner.view), inside)
                    } else { XCTAssertFalse(inside) }
                }
            }
        }
        XCTAssertEqual(owner.phase, .manual); checkVisiblePathHits()
        owner.request(open: true); wait(0.05); checkVisiblePathHits()
        wait(0.95); checkVisiblePathHits()
        owner.request(open: false); wait(0.05); checkVisiblePathHits()
        wait(0.75)
        XCTAssertNil(owner.view.hitTest(CGPoint(x: 8, y: 400), with: nil))
        XCTAssertFalse(owner.isRunning)
        // Reuse the existing three-stage/isolation and owner-release tests too.
    }
}
