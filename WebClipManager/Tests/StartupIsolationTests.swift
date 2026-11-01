import XCTest
import SwiftUI
import UIKit
@testable import WebClipManager

final class StartupIsolationTests: XCTestCase {
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
