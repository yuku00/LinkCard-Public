import XCTest
import SwiftUI
import UIKit
@testable import WebClipManager

final class StartupIsolationTests: XCTestCase {
    func testLogRejectsSharedHomeAndUsesOnlyAppSubdirectory() {
        XCTAssertNil(StartupLog.logURL(documents: URL(fileURLWithPath: "/var/mobile/Documents")))
        XCTAssertNil(StartupLog.logURL(documents: URL(fileURLWithPath: "/var/tmp")))
        let container = URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555/Documents")
        XCTAssertNil(StartupLog.logURL(documents: container))
        let log = StartupLog.logURL(documents: AppPaths.documents)
        XCTAssertNotNil(log)
        XCTAssertEqual(log?.lastPathComponent, "startup-build7.log")
        XCTAssertEqual(log?.deletingLastPathComponent(), AppPaths.documents)
    }

    @MainActor
    func testUIKitControllerDoesNotInstantiateHostingController() {
        let controller = StartupViewController()
        controller.loadViewIfNeeded()
        XCTAssertNil(controller.presentedViewController)
        XCTAssertTrue(controller.children.isEmpty)
    }
    @MainActor
    func testOriginalViewsRenderWithoutAutomaticReading() {
        let model = Model()
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIHostingController(rootView: ManagerView(model: model))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(model.readState, "notRead")
        XCTAssertFalse(model.busy)
        XCTAssertTrue(model.scan.clips.isEmpty)
        window.isHidden = true
    }
}
