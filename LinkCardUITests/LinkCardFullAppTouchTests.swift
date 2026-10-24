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
            app.launchArguments.append("-DrawerClickAudit")
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
    private func wait(_ element: XCUIElement, _ predicate: String, seconds: Double = 6) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: seconds), .completed, element.debugDescription)
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
    private func reveal(_ element: XCUIElement) {
        for attempt in 0..<8 {
            if element.exists && element.isHittable { return }
            // Settings tests visit wallpaper then controls above it. Always
            // swiping upward can never reveal an earlier off-screen slider.
            let above = element.exists && !element.frame.isEmpty
                ? element.frame.midY < app.frame.midY : attempt >= 4
            print("FULLAPP reveal id=\(element.identifier) attempt=\(attempt) above=\(above)")
            drag(CGVector(dx: 0.78, dy: above ? 0.38 : 0.72),
                 CGVector(dx: 0.78, dy: above ? 0.72 : 0.38))
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
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
    func testAIdleCoordinateMenuCompletesWithoutAnimationTimeout() {
        // Default production appearance, no injected state or idle overrides.
        open(); capture("idle-regression-sidebar"); close()
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
        XCTAssertTrue(["0", "1"].contains(original), "Expected a binary native switch value")
        let changedDither = original == "0" ? "1" : "0"
        capture("dither-before-real-leaf-tap")
        tap(dither) // Exactly one dynamic-frame coordinate tap, not the outer row.
        waitForValue(dither, row: ditherRow, expected: changedDither)
        XCTAssertNotEqual(dither.value as? String, originalDither, "The real switch must toggle")
        XCTAssertEqual(ditherRow.value as? String, changedDither, "Outer row must reflect the native switch")
        print("FULLAPP dither changed leaf=\(String(describing: dither.value)) row=\(String(describing: ditherRow.value))")
        capture("dither-after-one-real-leaf-tap")
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
            app.launchArguments = ["--uitest-texture", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance.blur", "0", "-appearance.veil", "0.25", "-appearance.blur.migrated.v2", "YES", "-appearance.blur.controls.v2", "\(strength)", "-appearance.blur.workbench.v2", "0"]
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
