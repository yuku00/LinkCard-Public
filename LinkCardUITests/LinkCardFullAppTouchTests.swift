// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import UIKit

final class LinkCardFullAppTouchTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if name.contains("testSidebarActionsTabsSettingsAndSafety") {
            app.launchArguments += ["-DrawerClickAudit", "-nfc.confirmBeforeSend.v1", "YES"]
        }
        app.launch() // Real App / WindowGroup / scene, never a forced replacement root.
        XCTAssertTrue(app.buttons["fusion.menu"].waitForExistence(timeout: 15), app.debugDescription)
    }
    override func tearDownWithError() throws {
        capture("final-full-window")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "actual-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
        app.terminate()
    }
    private func wait(_ element: XCUIElement, _ predicate: String, seconds: Double = 6,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: seconds), .completed,
                       "Timed out waiting for \(predicate)", file: file, line: line)
    }
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 6), app.debugDescription)
        if element.identifier == "drawer.2" {
            print("[DRAWER-AUDIT-XCUI] device enabled=\(element.isEnabled) frame=\(element.frame) hittable=\(element.isHittable)")
            capture("sidebar-before-device-hit-check")
        }
        wait(element, "hittable == true")
        let frame = element.frame
        let identifier = element.identifier // Cache before a tap can dismiss this element.
        XCTAssertFalse(frame.isEmpty)
        XCTAssertTrue(element.isEnabled)
        XCTAssertTrue(app.frame.contains(CGPoint(x: frame.midX, y: frame.midY)),
                      "Physical tap centre must be visible; never substitute a nearby control")
        print("FULLAPP event begin tap=\(identifier) frame=\(frame)")
        let started = ProcessInfo.processInfo.systemUptime
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX-app.frame.minX, dy: frame.midY-app.frame.minY)).tap()
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        print("FULLAPP event end tap=\(identifier) elapsed=\(elapsed)s")
        XCTAssertLessThan(elapsed, 15, "Real coordinate event blocked waiting for app animations; never disable quiescence")
    }
    private func panel(_ value: String) {
        let panel = app.descendants(matching: .any).matching(identifier: "workbench.panel").firstMatch
        wait(panel, "exists == true AND value == '\(value)'")
    }
    private func open() { tap(app.buttons["fusion.menu"]); wait(app.buttons["fusion.close"], "hittable == true") }
    private func close() { tap(app.buttons["fusion.close"]); wait(app.buttons["fusion.close"], "hittable == false") }
    private func drag(_ from: CGVector, _ to: CGVector) {
        app.coordinate(withNormalizedOffset: from).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: to))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func contentViewport() -> CGRect {
        let panel = app.descendants(matching: .any).matching(identifier: "workbench.panel").firstMatch.frame
        let handle = app.buttons["workbench.handle"].frame
        let settings = app.buttons["fusion.settings"]
        let top = settings.exists && settings.isHittable ? max(handle.maxY, settings.frame.maxY) : handle.maxY
        let tabTop = ["tab.0", "tab.1", "tab.2"].map { app.buttons[$0].frame.minY }.min()!
        // FusionShell places content strictly between the header and tab padding.
        return CGRect(x: panel.minX, y: top, width: panel.width,
                      height: max(0, tabTop - 12 - top)).intersection(app.frame)
    }
    private func reveal(_ element: XCUIElement) {
        for attempt in 0..<8 {
            let viewport = contentViewport()
            let frame = element.exists ? element.frame : .zero
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            if element.exists && element.isHittable && viewport.contains(centre) { return }
            let above = element.exists && !frame.isEmpty ? frame.midY < viewport.midY : attempt >= 4
            // MistPage and creationPage inset content by 14/16 points; scroll in
            // the 8-point gutter, not through the slider tracks at screen x=.78.
            let x = viewport.minX + 8
            let low = viewport.minY + viewport.height * 0.8
            let high = viewport.minY + viewport.height * 0.2
            XCTAssertGreaterThan(low - high, 40)
            let sliders = ["blur.controls", "blur.workbench", "blur.sidebar"].map { app.sliders[$0] }
                .filter { $0.exists && $0.isHittable }
            let values = sliders.map { $0.normalizedSliderPosition }
            for slider in sliders { XCTAssertLessThan(x, slider.frame.minX, "Scroll gutter must not hit a slider") }
            screenPoint(CGPoint(x: x, y: above ? high : low)).press(forDuration: 0.05,
                thenDragTo: screenPoint(CGPoint(x: x, y: above ? low : high)))
            for (slider, before) in zip(sliders, values) {
                XCTAssertEqual(slider.normalizedSliderPosition, before, accuracy: 0.001,
                               "Revealing content must not edit a blur preference")
            }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
        XCTAssertTrue(contentViewport().contains(CGPoint(x: element.frame.midX, y: element.frame.midY)),
                      "Coordinate tap centre must be inside visible workbench content")
    }
    // SwiftUI can expose a labelled row and the native control as the same AX
    // type. Never use a row's centre as the switch or slider touch target.
    private func visibleLeafControl(_ row: XCUIElement, type: XCUIElement.ElementType) throws -> XCUIElement {
        reveal(row)
        let descendants = row.descendants(matching: type).allElementsBoundByIndex
        // AX ancestry establishes ownership, not rectangle containment.
        // A semantic child may extend beyond the enclosing row's frame.
        // Do not enlarge a tolerance, guess by aspect ratio, or search the app.
        let pool = descendants.isEmpty ? (row.elementType == type ? [row] : []) : descendants
        let candidates = pool.filter { element in
            element.exists && element.descendants(matching: type).count == 0
        }
        print("FULLAPP AX row id=\(row.identifier) frame=\(row.frame) value=\(String(describing: row.value)) leafCandidates=\(candidates.count)")
        XCTAssertEqual(candidates.count, 1, "Require one semantic leaf control, never silently fall back to a row: \(row.debugDescription)")
        let control = try XCTUnwrap(candidates.count == 1 ? candidates.first : nil)
        XCTAssertTrue(control.isHittable, "Unique semantic leaf must be visible and hittable")
        XCTAssertFalse(control.frame.isEmpty)
        XCTAssertTrue(control.isEnabled)
        print("FULLAPP AX leaf type=\(type.rawValue) frame=\(control.frame) value=\(String(describing: control.value))")
        return control
    }
    private func waitForValue(_ element: XCUIElement, row: XCUIElement, expected: String) {
        let predicate = NSPredicate { _, _ in
            element.value as? String == expected && row.value as? String == expected
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 6), .completed,
                       "One physical tap must produce consistent inner/outer value \(expected); no tap retry")
    }
    private func slide(_ row: XCUIElement, to position: CGFloat) throws {
        let slider = try visibleLeafControl(row, type: .slider)
        XCTAssertTrue((0...1).contains(position))
        let old = try XCTUnwrap(slider.value as? String)
        let oldPosition = slider.normalizedSliderPosition
        let oldRow = row.value as? String
        XCTAssertNotEqual(oldPosition, position, "Requested drag must change actual thumb state")
        let f = slider.frame, origin = app.frame.origin
        // Prefer a real AX thumb when UIKit exposes one. Do not mistake a
        // labelled enclosing row or track for the thumb. Some iOS versions
        // expose only the leaf slider: XCTest's public adjust API synthesizes
        // a physical thumb drag; it does not set a binding or an AX value.
        let thumbs = slider.descendants(matching: .any).allElementsBoundByIndex.filter { element in
            let name = (element.identifier + " " + element.label).lowercased()
            let r = element.frame
            return element.exists && element.isHittable && !r.isEmpty
                && (name.contains("thumb") || name.contains("滑块")
                    || (element.elementType == .button && element.descendants(matching: .button).count == 0))
        }
        XCTAssertLessThanOrEqual(thumbs.count, 1, "Ambiguous AX thumbs: \(slider.debugDescription)")
        print("FULLAPP slider id=\(row.identifier) leafFrame=\(f) old=\(old) target=\(position) AXthumbs=\(thumbs.count)")
        if let thumb = thumbs.first {
            let t = thumb.frame
            let endX = f.minX + t.width / 2 + (f.width - t.width) * position
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: t.midX-origin.x, dy: t.midY-origin.y))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: endX-origin.x, dy: t.midY-origin.y)))
        } else {
            slider.adjust(toNormalizedSliderPosition: position)
            // XCTest's synthesized drag can land a few percent away from the
            // requested fraction. Keep the original 0.02 acceptance bound.
            // At most two measured corrections; never write a binding/AX value.
            let landed = slider.normalizedSliderPosition
            if abs(landed - position) > 0.02 {
                let corrected = min(1, max(0, position + position - landed))
                XCTAssertNotEqual(corrected, position)
                slider.adjust(toNormalizedSliderPosition: corrected)
                let secondLanding = slider.normalizedSliderPosition
                // Observed .18 -> .15, then .21 -> .21: a full offset
                // overshoots. Interpolate the two actual responses instead of
                // alternating requests. Only interpolate a bracketed target;
                // a nonmonotonic or unmoving control must fail, not be retried.
                let response = secondLanding - landed
                if abs(secondLanding - position) > 0.02 && abs(response) > 0.001 {
                    let fraction = (position - landed) / response
                    if (0...1).contains(fraction) {
                        let interpolated = position + (corrected - position) * fraction
                        slider.adjust(toNormalizedSliderPosition: interpolated)
                    }
                }
            }
        }
        let changed = NSPredicate { _, _ in
            guard let value = slider.value as? String, value != old else { return false }
            // When the wrapper exposes the same value schema, require its
            // readback to converge too, within the original six-second bound.
            return oldRow != old || row.value as? String == value
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: slider)], timeout: 6), .completed)
        XCTAssertNotEqual(slider.value as? String, old, "A real thumb drag must change the setting")
        let newPosition = slider.normalizedSliderPosition
        XCTAssertGreaterThan((newPosition - oldPosition) * (position - oldPosition), 0,
                             "Actual thumb must move in the requested direction")
        XCTAssertLessThan(abs(newPosition - position), abs(oldPosition - position),
                          "Actual thumb must finish closer to the requested position")
        print("FULLAPP slider result id=\(row.identifier) old=\(old) new=\(String(describing: slider.value)) normalized=\(oldPosition)->\(newPosition)")
    }
    private func screenPoint(_ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
    }
    private func verticalHandle(_ expanded: Bool) {
        let handle = app.buttons["workbench.handle"]
        wait(handle, "hittable == true")
        let start = CGPoint(x: handle.frame.midX, y: handle.frame.midY)
        let endY = expanded ? app.frame.minY + 105 : app.frame.maxY - 105
        let started = ProcessInfo.processInfo.systemUptime
        screenPoint(start).press(forDuration: 0.05,
            thenDragTo: screenPoint(CGPoint(x: start.x, y: endY)),
            withVelocity: .slow, thenHoldForDuration: 0.15)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 15,
                          "Vertical handle drag must settle with default quiescence")
        panel(expanded ? "expanded" : "compact")
    }
    private func verticalContent(_ value: String) {
        let container = app.descendants(matching: .any).matching(identifier: "workbench.panel").firstMatch
        let f = container.frame
        // Between the handle/header and tabs, never on the drawer or handle.
        let top = f.minY + (value == "expanded" ? 100 : 54)
        let bottom = min(f.maxY - 90, app.frame.maxY - 100)
        XCTAssertGreaterThan(bottom - top, 40)
        let lower = CGPoint(x: f.minX + 18, y: bottom)
        let upper = CGPoint(x: lower.x, y: top)
        screenPoint(lower).press(forDuration: 0.05, thenDragTo: screenPoint(upper))
        panel(value)
        screenPoint(upper).press(forDuration: 0.05, thenDragTo: screenPoint(lower))
        panel(value)
    }
    private func responsiveTabTap() {
        // A real coordinate tap with a visible page change, not just isHittable.
        tap(app.buttons["tab.1"])
        XCTAssertTrue(app.staticTexts["你的文件，安静留在本机。"].waitForExistence(timeout: 6))
        tap(app.buttons["tab.0"])
        XCTAssertTrue(app.staticTexts["200 × 200 · 单色电子纸"].waitForExistence(timeout: 6))
    }
    private func verifyWorkbenchVerticalHandleRoundTripsAndReversal() {
        panel("compact")
        for _ in 0..<4 {
            verticalHandle(true)
            verticalHandle(false)
        }
        // A sub-threshold displacement returns to the same detent, then reverse.
        let handle = app.buttons["workbench.handle"]
        let p = CGPoint(x: handle.frame.midX, y: handle.frame.midY)
        screenPoint(p).press(forDuration: 0.05,
            thenDragTo: screenPoint(CGPoint(x: p.x, y: p.y - 24)),
            withVelocity: .slow, thenHoldForDuration: 0.2)
        panel("compact")
        responsiveTabTap()
        verticalHandle(false); verticalHandle(true); verticalHandle(false)
        open(); close() // A subsequent actual menu tap must also respond.
    }
    private func verifyWorkbenchVerticalContentScrollAndSettingsHandle() {
        panel("compact"); verticalContent("compact")
        verticalHandle(true); verticalContent("expanded")
        responsiveTabTap()
        tap(app.buttons["fusion.settings"]); panel("expanded")
        verticalContent("expanded")
        verticalHandle(false); verticalContent("compact")
        verticalHandle(true)
        // Verify content really scrolls, not just that the root stays put.
        let wallpaper = app.sliders["blur.wallpaper"]
        reveal(wallpaper); XCTAssertTrue(wallpaper.isHittable); panel("expanded")
        let controls = app.sliders["blur.controls"]
        reveal(controls); XCTAssertTrue(controls.isHittable); panel("expanded")
        verticalHandle(false); verticalHandle(true)
        responsiveTabTap(); open(); close()
    }
    private func verifyWorkbenchVerticalWithKeyboardAndLifecycle() {
        verticalHandle(true)
        let note = app.buttons["便签"].firstMatch
        reveal(note); tap(note)
        let editor = app.textViews["便签文字"]
        reveal(editor); tap(editor)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 6))
        panel("expanded")
        verticalHandle(false); verticalHandle(true)
        tap(app.buttons["tab.1"])
        XCTAssertTrue(app.staticTexts["你的文件，安静留在本机。"].waitForExistence(timeout: 6))
        wait(app.keyboards.firstMatch, "exists == false")
        verticalHandle(false); verticalHandle(true)
        XCUIDevice.shared.press(.home); app.activate()
        verticalHandle(false); verticalHandle(true)
        open(); close()
    }
    private func verifyPreviewPhotoPickerCancelAfterVerticalDrags() {
        verticalHandle(true); verticalHandle(false); verticalHandle(true)
        for title in ["日期", "便签"] {
            let template = app.buttons[title].firstMatch
            reveal(template); tap(template)
            let note = app.textViews["便签文字"]
            let oldText = title == "便签" ? note.value as? String : nil
            let send = app.buttons["create.send"]
            reveal(send); wait(send, "enabled == true")
            let preview = app.buttons["create.preview"]
            reveal(preview)
            let before = pixels(preview.screenshot().image, CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
            tap(preview)
            let cancel = app.buttons["取消"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 6), "Preview must open the system PhotosPicker")
            tap(cancel)
            wait(preview, "hittable == true")
            XCTAssertEqual(pixels(preview.screenshot().image, CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)), before,
                           "Cancelling must not clear or change the rendered pixels")
            XCTAssertTrue(template.isSelected, "Cancelling must not switch to the photo template")
            if let oldText { XCTAssertEqual(note.value as? String, oldText) }
            XCTAssertFalse(app.buttons["取消会话"].exists, "Choosing/cancelling a photo must never start NFC")
            panel("expanded")
        }
        verticalHandle(false); verticalHandle(true)
        responsiveTabTap(); open(); close()
    }
    private func verifySendConfirmationPreferencePersistsWithoutStartingNFC() throws {
        func setting() throws -> (XCUIElement, XCUIElement) {
            verticalHandle(true); tap(app.buttons["fusion.settings"])
            let section = app.buttons["发送前的小提醒"].firstMatch
            reveal(section); tap(section)
            let row = app.switches.matching(identifier: "send.confirmBeforeSend").firstMatch
            return (row, try visibleLeafControl(row, type: .switch))
        }
        let (row, control) = try setting()
        let original = try XCTUnwrap(control.value as? String)
        XCTAssertTrue(["0", "1"].contains(original))
        let changed = original == "0" ? "1" : "0"
        tap(control); waitForValue(control, row: row, expected: changed)
        app.terminate(); app.launch()
        let (restoredRow, restoredControl) = try setting()
        XCTAssertEqual(restoredControl.value as? String, changed)
        tap(restoredControl); waitForValue(restoredControl, row: restoredRow, expected: original)
        XCTAssertFalse(app.buttons["取消会话"].exists)
        responsiveTabTap()
    }
    private func verifyFourBlurChannelsRemainIndependentAcrossRelaunch() throws {
        verticalHandle(true); tap(app.buttons["fusion.settings"])
        let controls = app.sliders["blur.controls"]
        let sidebar = app.sliders["blur.sidebar"]
        let workbench = app.sliders["blur.workbench"]
        let wallpaper = app.sliders["blur.wallpaper"]
        func value(_ row: XCUIElement) throws -> CGFloat {
            try visibleLeafControl(row, type: .slider).normalizedSliderPosition
        }
        let originalControls = try value(controls), originalSidebar = try value(sidebar)
        let originalWorkbench = try value(workbench), originalWallpaper = try value(wallpaper)
        func set(_ row: XCUIElement, _ target: CGFloat) throws {
            if abs(try value(row) - target) > 0.005 { try slide(row, to: target) }
            XCTAssertEqual(try value(row), target, accuracy: 0.02,
                           "Physical slider target: \(row.identifier)")
        }
        for strength in [CGFloat(0), 0.5, 1] {
            try set(sidebar, strength)
            XCTAssertEqual(try value(controls), originalControls, accuracy: 0.02)
            XCTAssertEqual(try value(workbench), originalWorkbench, accuracy: 0.02)
            XCTAssertEqual(try value(wallpaper), originalWallpaper, accuracy: 0.02)
            open(); capture("sidebar-strength-\(strength)"); close()
        }
        try set(controls, originalControls < 0.5 ? 1 : 0)
        XCTAssertEqual(try value(sidebar), 1, accuracy: 0.02)
        app.terminate(); app.launch()
        verticalHandle(true); tap(app.buttons["fusion.settings"])
        XCTAssertEqual(try value(sidebar), 1, accuracy: 0.02)
        XCTAssertEqual(try value(workbench), originalWorkbench, accuracy: 0.02)
        XCTAssertEqual(try value(wallpaper), originalWallpaper, accuracy: 0.02)
        try set(controls, originalControls); try set(sidebar, originalSidebar)
        responsiveTabTap(); open(); close()
    }
    func testAIdleCoordinateMenuCompletesWithoutAnimationTimeout() throws {
        // Default production appearance, no injected state or idle overrides.
        open(); capture("idle-regression-sidebar"); close()
        verifyWorkbenchVerticalHandleRoundTripsAndReversal()
        try verifySendConfirmationPreferencePersistsWithoutStartingNFC()
        XCUIDevice.shared.press(.home); app.activate()
        open(); close()
    }
    func testRealLaunchCoordinatesSidebarAndLifecycle() {
        panel("compact")
        tap(app.buttons["workbench.handle"]); panel("expanded")
        tap(app.buttons["workbench.handle"]); panel("compact")
        tap(app.buttons["workbench.handle"]); panel("expanded")
        for _ in 0..<3 {
            open(); capture("full-window-sidebar-open")
            drag(CGVector(dx: 0.30, dy: 0.68), CGVector(dx: 0.30, dy: 0.42))
            // Vertical scrolling must not be consumed as drawer close.
            XCTAssertTrue(app.buttons["drawer.1"].exists)
            drag(CGVector(dx: 0.30, dy: 0.42), CGVector(dx: 0.30, dy: 0.68))
            close()
        }
        drag(CGVector(dx: 0.02, dy: 0.40), CGVector(dx: 0.76, dy: 0.40))
        wait(app.buttons["fusion.close"], "hittable == true"); close()
        tap(app.buttons["fusion.avatar"])
        tap(app.buttons["profile.done"])
        wait(app.buttons["profile.done"], "exists == false")
        open(); close()
        XCUIDevice.shared.press(.home); app.activate()
        wait(app.buttons["fusion.menu"], "hittable == true")
        open(); close()
        tap(app.buttons["workbench.handle"]); panel("compact")
        verifyWorkbenchVerticalContentScrollAndSettingsHandle()
        verifyWorkbenchVerticalWithKeyboardAndLifecycle()
    }
    func testSidebarActionsTabsSettingsAndSafety() throws {
        for entry in [(1, "你的文件，安静留在本机。"), (2, "前台保持连接，按需读取。"), (0, "200 × 200 · 单色电子纸")] {
            open(); tap(app.buttons["drawer.\(entry.0)"])
            XCTAssertTrue(app.staticTexts[entry.1].waitForExistence(timeout: 6))
            panel("expanded"); wait(app.buttons["fusion.close"], "hittable == false")
        }
        tap(app.buttons["tab.1"])
        XCTAssertTrue(app.staticTexts["你的文件，安静留在本机。"].waitForExistence(timeout: 6))
        tap(app.buttons["tab.2"])
        XCTAssertTrue(app.staticTexts["前台保持连接，按需读取。"].waitForExistence(timeout: 6))
        let read = app.buttons["device.read"]; reveal(read)
        XCTAssertFalse(read.isEnabled, "No device means read stays disabled; no permission bypass")
        // Open/close a real settings sheet before the real identify tap.
        let settings = app.buttons["device.settings"]; reveal(settings); tap(settings)
        let done = app.buttons["device.settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 6)); tap(done)
        wait(done, "exists == false")
        verifyRealIdentifyGuard()
        XCTAssertFalse(read.isEnabled)
        // Never tap scan/authorize/connect on an unattended simulator.
        tap(app.buttons["tab.0"])
        // Dithering belongs to Photo mode, not the default Date editor. Enter
        // through the user's mode button; never open Photos or grant permission.
        let photoMode = app.buttons["照片"]; reveal(photoMode); tap(photoMode)
        let ditherRow = app.switches.matching(identifier: "create.dither").firstMatch
        let dither = try visibleLeafControl(ditherRow, type: .switch)
        XCTAssertTrue(dither.isEnabled)
        let originalDither = dither.value as? String
        XCTAssertNotNil(originalDither)
        let original = try XCTUnwrap(originalDither)
        XCTAssertEqual(original, "1", "A fresh editor defaults to dithering enabled")
        let changedDither = original == "0" ? "1" : "0"
        capture("dither-before-real-leaf-tap")
        tap(dither) // Exactly one dynamic-frame coordinate tap, not the outer row.
        waitForValue(dither, row: ditherRow, expected: changedDither)
        XCTAssertNotEqual(dither.value as? String, originalDither, "The real switch must toggle")
        XCTAssertEqual(ditherRow.value as? String, changedDither, "Outer row must reflect the native switch")
        print("FULLAPP dither changed leaf=\(String(describing: dither.value)) row=\(String(describing: ditherRow.value))")
        capture("dither-after-one-real-leaf-tap")
        let temporaryDate = app.buttons["日期"].firstMatch
        reveal(temporaryDate); tap(temporaryDate)
        reveal(photoMode); tap(photoMode); reveal(ditherRow)
        waitForValue(dither, row: ditherRow, expected: changedDither)
        tap(dither) // One restoring tap; never retry a failed state change.
        waitForValue(dither, row: ditherRow, expected: original)
        XCTAssertEqual(dither.value as? String, originalDither, "Restore the user's original toggle value")
        XCTAssertEqual(ditherRow.value as? String, originalDither)
        print("FULLAPP dither restored leaf=\(String(describing: dither.value)) row=\(String(describing: ditherRow.value))")
        capture("dither-restored-after-second-real-leaf-tap")
        let dateMode = app.buttons["日期"].firstMatch; reveal(dateMode); tap(dateMode)
        let send = app.buttons["create.send"]; reveal(send); wait(send, "enabled == true")
        tap(send)
        XCTAssertTrue(app.buttons["通过 NFC 发送"].waitForExistence(timeout: 6))
        tap(app.buttons["取消"])
        XCTAssertFalse(app.buttons["通过 NFC 发送"].exists)
        let status = app.staticTexts["nfc.status"]; reveal(status)
        XCTAssertEqual(status.label, "准备好内容，即可发送到设备", "Cancel must not start a CoreNFC session")
        tap(app.buttons["fusion.settings"])
        let wallpaper = app.sliders["blur.wallpaper"]
        try slide(wallpaper, to: 0.75)
        let controls = app.sliders["blur.controls"]
        try slide(controls, to: 0.2)
        let workbench = app.sliders["blur.workbench"]
        try slide(workbench, to: 0.45)
        XCTAssertTrue(app.sliders["blur.controls"].exists)
        capture("settings-sliders-real-touch")
        try verifyFourBlurChannelsRemainIndependentAcrossRelaunch()
        verifyPreviewPhotoPickerCancelAfterVerticalDrags()
        // Four-blur persistence check relaunched the real app. Photos has now
        // dismissed; verify the first identify action in that fresh BLE session.
        tap(app.buttons["tab.2"])
        verifyRealIdentifyGuard()
    }
    private func verifyRealIdentifyGuard() {
        let status = app.staticTexts["device.identify.status"]; reveal(status)
        let before = status.label
        let identify = app.buttons["device.identify"]; reveal(identify)
        XCTAssertTrue(identify.isEnabled, "Disconnected tap must reach the production guard")
        tap(identify) // One physical coordinate tap; never invoke an action/test hook.
        let changed = NSPredicate(format: "label != %@ AND label != ''", before)
        expectation(for: changed, evaluatedWith: status)
        waitForExpectations(timeout: 3)
        reveal(status)
        XCTAssertTrue(status.isHittable, "The real guard result must be visible beside the button")
        XCTAssertFalse(app.buttons["device.identify.cancel"].exists)
        XCTAssertFalse(app.buttons["已取下卡片，读取一次版本"].exists)
        XCTAssertFalse(app.buttons["通过 NFC 发送"].exists)
        XCTAssertFalse(app.buttons["取消会话"].exists)
        // No status/UID values or card screenshots are written to public logs.
    }
    private func pixels(_ image: UIImage, _ rect: CGRect) -> [UInt8] {
        let cg = image.cgImage!
        let roi = CGRect(x:rect.minX*CGFloat(cg.width), y:rect.minY*CGFloat(cg.height), width:rect.width*CGFloat(cg.width), height:rect.height*CGFloat(cg.height)).integral
        let crop = cg.cropping(to:roi)!
        var bytes = [UInt8](repeating:0,count:crop.width*crop.height*4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data:raw.baseAddress,width:crop.width,height:crop.height,bitsPerComponent:8,bytesPerRow:crop.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(crop,in:CGRect(x:0,y:0,width:crop.width,height:crop.height))
        }
        return bytes
    }
    private func difference(_ a:[UInt8], _ b:[UInt8]) -> Double {
        XCTAssertEqual(a.count,b.count)
        return zip(a,b).reduce(0.0) { $0 + abs(Double($1.0)-Double($1.1)) } / Double(a.count)
    }
    func testFullWindowTextureBlurZeroHalfFull() {
        var middle:[[UInt8]] = [], top:[[UInt8]] = [], bottom:[[UInt8]] = []
        for strength in [0,50,100] {
            app.terminate()
            app.launchArguments = ["--uitest-texture", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance.blur", "0", "-appearance.veil", "0.25", "-appearance.blur.migrated.v2", "YES", "-appearance.blur.controls.v2", "0", "-appearance.blur.sidebar.v1", "\(strength)", "-appearance.blur.workbench.v2", "0"]
            app.launch()
            XCTAssertTrue(app.buttons["fusion.menu"].waitForExistence(timeout:15))
            capture("texture-closed-\(strength)")
            open()
            // Wait for physical three-stage motion, not a forced phase/request call.
            let stable = expectation(description:"full window composite settle")
            DispatchQueue.main.asyncAfter(deadline:.now()+1.2) { stable.fulfill() }
            wait(for:[stable],timeout:3)
            let shot = app.screenshot()
            let attachment = XCTAttachment(screenshot:shot)
            attachment.name = "texture-full-window-blur-\(strength)"; attachment.lifetime = .keepAlways; add(attachment)
            middle.append(pixels(shot.image,CGRect(x:0.06,y:0.75,width:0.35,height:0.1)))
            top.append(pixels(shot.image,CGRect(x:0.26,y:0.018,width:0.20,height:0.018)))
            bottom.append(pixels(shot.image,CGRect(x:0.06,y:0.965,width:0.35,height:0.018)))
            XCUIDevice.shared.press(.home); app.activate()
            wait(app.buttons["fusion.close"],"hittable == true")
            capture("texture-foreground-blur-\(strength)")
            close()
        }
        let report = ["middle0-50":difference(middle[0],middle[1]), "middle50-100":difference(middle[1],middle[2]), "top0-100":difference(top[0],top[2]), "bottom0-100":difference(bottom[0],bottom[2])]
        let a = XCTAttachment(string:"Full-window pixel differences: \(report)"); a.name="full-window-blur-metrics"; a.lifetime = .keepAlways; add(a)
        for (name,value) in report { XCTAssertGreaterThan(value,0.7,"Full-window blur/full-height missing: \(name)") }
    }
}
