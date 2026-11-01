import XCTest
import SwiftUI
import UIKit
@testable import WebClipManager

final class DocumentUIIsolationTests: XCTestCase {
    @MainActor
    private func render<V: View>(_ view: V, verify: () throws -> Void) rethrows {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.loadViewIfNeeded()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertNotNil(host.view.window)
        try verify()
    }

    @MainActor
    func testUnavailablePagesNeverConstructDocumentStateTypesOrModifiers() {
        let ready = AppPaths.ready
        AppPaths.ready = false
        defer { AppPaths.ready = ready }
        DocumentUIProbe.reset()
        let model = Model()
        let before = StartupLog.exportText
        let notesState = NotesReadDiagnostic.capture().state
        XCTAssertTrue(DocumentUIProbe.snapshot.isEmpty, "Model must not allocate a document")
        render(ManagerView(model: model)) { XCTAssertTrue(DocumentUIProbe.snapshot.isEmpty) }
        render(NotesView()) { XCTAssertTrue(DocumentUIProbe.snapshot.isEmpty) }
        render(NavigationStack { DiagnosticsView(model: model) }) { XCTAssertTrue(DocumentUIProbe.snapshot.isEmpty) }
        XCTAssertEqual(model.readState, "notRead")
        XCTAssertTrue(model.scan.clips.isEmpty)
        for marker in ["S9_REFRESH_ENTERED", "S10_REPOSITORY_SCAN_ENTERED"] {
            XCTAssertEqual(StartupLog.exportText.components(separatedBy: marker).count,
                           before.components(separatedBy: marker).count)
        }
        XCTAssertEqual(NotesReadDiagnostic.capture().state, notesState)
    }

    @MainActor
    func testAvailablePagesExerciseRealDocumentConstructionPositiveControl() {
        let ready = AppPaths.ready
        AppPaths.ready = true
        defer { AppPaths.ready = ready }
        let model = Model()
        DocumentUIProbe.reset()
        render(ManagerView(model: model)) {
            for event in ["manager.state", "manager.types", "manager.modifiers", "backup.document"] {
                XCTAssertGreaterThan(DocumentUIProbe.snapshot[event, default: 0], 0, event)
            }
        }
        DocumentUIProbe.reset()
        render(NotesView()) {
            for event in ["notes.state", "notes.types", "notes.modifiers"] {
                XCTAssertGreaterThan(DocumentUIProbe.snapshot[event, default: 0], 0, event)
            }
        }
        DocumentUIProbe.reset()
        render(NavigationStack { DiagnosticsView(model: model) }) {
            for event in ["diagnostics.state", "diagnostics.types", "diagnostics.modifiers", "backup.document"] {
                XCTAssertGreaterThan(DocumentUIProbe.snapshot[event, default: 0], 0, event)
            }
        }
        // No picker is presented and no source files are read in this control.
        XCTAssertEqual(model.readState, "notRead")
    }

    @MainActor
    func testNonreadyCompleteRootModalPresentationAndBothTabsWithoutScan() throws {
        let ready = AppPaths.ready
        AppPaths.ready = false
        defer { AppPaths.ready = ready }
        let before = StartupLog.exportText
        let environment = ProcessInfo.processInfo.environment
        let notesState = NotesReadDiagnostic.capture().state
        DocumentUIProbe.reset()
        let window = UIWindow(frame: UIScreen.main.bounds)
        let startup = StartupViewController()
        window.rootViewController = startup
        window.makeKeyAndVisible()
        startup.loadViewIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        // Deliberately bypass prepare(), which validates the simulator's real
        // container. Keep the build9 modal style and complete production RootView.
        let host = UIHostingController(rootView: RootView())
        let presented = expectation(description: "complete nonready RootView presented")
        startup.present(host, animated: true) { presented.fulfill() }
        wait(for: [presented], timeout: 15)
        defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
        func tabs(_ vc: UIViewController) -> UITabBarController? {
            if let tab = vc as? UITabBarController { return tab }
            return vc.children.compactMap { tabs($0) }.first
        }
        let tab = try XCTUnwrap(tabs(host))
        XCTAssertEqual(tab.viewControllers?.count, 2)
        XCTAssertEqual(tab.tabBar.items?.map(\.title), ["书签管理", "备忘录导出"])
        tab.selectedIndex = 1
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(tab.selectedIndex, 1)
        XCTAssertNotNil(tab.selectedViewController?.view.window)
        XCTAssertTrue(StartupLog.exportText.contains("S6_ROOT_ON_APPEAR"))
        XCTAssertTrue(DocumentUIProbe.snapshot.isEmpty, "Nonready full root must never create document UI")
        for marker in ["S9_REFRESH_ENTERED", "S10_REPOSITORY_SCAN_ENTERED"] {
            XCTAssertEqual(StartupLog.exportText.components(separatedBy: marker).count,
                           before.components(separatedBy: marker).count)
        }
        XCTAssertEqual(NotesReadDiagnostic.capture().state, notesState)
        XCTAssertEqual(ProcessInfo.processInfo.environment, environment)
    }
}
