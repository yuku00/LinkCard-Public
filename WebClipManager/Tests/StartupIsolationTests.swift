import XCTest
import SwiftUI
import UIKit
import Darwin
@testable import WebClipManager

final class StartupIsolationTests: XCTestCase {
    func testPrepareDoesNotChangeOSEnvironment() {
        func environment() -> [String: String] {
            var result: [String: String] = [:]
            for key in ["HOME", "CFFIXED_USER_HOME", "TMPDIR"] {
                result[key] = getenv(key).map { String(cString: $0) } ?? "<absent>"
            }
            return result
        }
        let before = environment()
        let home = NSHomeDirectory()
        let temporary = NSTemporaryDirectory()
        AppPaths.prepare()
        XCTAssertEqual(environment(), before)
        XCTAssertEqual(NSHomeDirectory(), home)
        XCTAssertEqual(NSTemporaryDirectory(), temporary)
    }

    @MainActor
    func testUIKitLogAndDiagnosticButtonWorkWithoutPathsOrSwiftUI() {
        let ready = AppPaths.ready
        AppPaths.ready = false
        defer { AppPaths.ready = ready }
        let controller = StartupViewController()
        controller.loadViewIfNeeded()
        XCTAssertNil(controller.presentedViewController)
        XCTAssertTrue(controller.children.isEmpty)
        XCTAssertTrue(controller.logView.isSelectable)
        XCTAssertFalse(controller.logView.isEditable)
        XCTAssertTrue(controller.copyButton.isEnabled)
        XCTAssertTrue(controller.diagnosticsButton.isEnabled)
        XCTAssertFalse(controller.logView.text.contains("sandboxChecks"))
        controller.diagnosticsButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(controller.logView.text.contains("sandboxChecks"))
        XCTAssertTrue(controller.logView.text.contains("fixedPaths"))
        XCTAssertTrue(controller.logView.text.contains("openErrno"))
        XCTAssertFalse(AppPaths.ready)
        XCTAssertNil(controller.presentedViewController)
        controller.copyButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(UIPasteboard.general.string, controller.logView.text)
    }

    @MainActor
    func testHomeButtonPresentsCompleteRootViewWithoutAutomaticScan() throws {
        let before = ProcessInfo.processInfo.environment
        let window = UIWindow(frame: UIScreen.main.bounds)
        let startup = StartupViewController()
        window.rootViewController = startup
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        startup.loadViewIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let priorScans = StartupLog.exportText.components(separatedBy: "S9_REFRESH_ENTERED").count
        startup.openButton.sendActions(for: .touchUpInside)
        let host = try XCTUnwrap(startup.presentedViewController as? UIHostingController<RootView>)
        host.view.layoutIfNeeded()
        // Simulator animation completion is asynchronous; wait for the actual
        // presentation callback rather than assuming a one-second wall clock.
        let presented = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            StartupLog.exportText.contains("S7_PRESENT_COMPLETED")
        }, object: nil)
        wait(for: [presented], timeout: 15)
        XCTAssertTrue(StartupLog.exportText.contains("S6_ROOT_ON_APPEAR"))
        XCTAssertTrue(StartupLog.exportText.contains("S6_MANAGER_ON_APPEAR_NO_SCAN"))
        XCTAssertTrue(StartupLog.exportText.contains("S7_PRESENT_COMPLETED"))
        XCTAssertEqual(StartupLog.exportText.components(separatedBy: "S9_REFRESH_ENTERED").count, priorScans)
        for key in ["HOME", "CFFIXED_USER_HOME", "TMPDIR"] {
            XCTAssertEqual(ProcessInfo.processInfo.environment[key], before[key])
        }
        host.dismiss(animated: false)
    }
}
