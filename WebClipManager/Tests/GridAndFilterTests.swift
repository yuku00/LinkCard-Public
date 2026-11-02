import XCTest
import UIKit
@testable import WebClipManager

@MainActor final class GridAndFilterTests: XCTestCase {
    func testManyClipsReuseAndScroll() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<130 {
            let dir = root.appendingPathComponent(String(format: "%03d.webclip", i))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let plist: [String: Any] = ["Title": String(format: "Synthetic %03d", i), "URL": "https://example.invalid/\(i / 2)", "FullScreen": i % 2 == 0]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: dir.appendingPathComponent("Info.plist"))
        }
        let list = BusinessList(mode: .clips, repository: Repository(root: root), notesLoader: { AppleNotesBatch() })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UINavigationController(rootViewController: list); window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        list.loadViewIfNeeded(); window.setNeedsLayout(); window.layoutIfNeeded()
        await list.loadItems(); window.layoutIfNeeded(); list.view.layoutIfNeeded()
        XCTAssertEqual(list.visibleClips.count, 130)
        XCTAssertEqual(list.tableView.numberOfRows(inSection: 1), 65)
        let first = try XCTUnwrap(list.tableView.cellForRow(at: IndexPath(row: 0, section: 1)) as? ClipGridRow)
        first.layoutIfNeeded(); first.grid.layoutIfNeeded()
        XCTAssertEqual(first.grid.numberOfItems(inSection: 0), 2)
        XCTAssertNotNil(first.grid.cellForItem(at: IndexPath(item: 0, section: 0)))
        XCTAssertNotNil(first.grid.cellForItem(at: IndexPath(item: 1, section: 0)))
        XCTAssertLessThan(list.tableView.visibleCells.count, 20)
        list.tableView.scrollToRow(at: IndexPath(row: 64, section: 1), at: .bottom, animated: false)
        list.view.layoutIfNeeded()
        let last = try XCTUnwrap(list.tableView.cellForRow(at: IndexPath(row: 64, section: 1)) as? ClipGridRow)
        last.layoutIfNeeded(); last.grid.layoutIfNeeded()
        XCTAssertEqual(last.grid.numberOfItems(inSection: 0), 2)
        XCTAssertNotNil(last.grid.cellForItem(at: IndexPath(item: 1, section: 0)))
        list.collectionView(last.grid, didSelectItemAt: IndexPath(item: 1, section: 0))
        XCTAssertEqual(list.selected.count, 1)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        list.view.layoutIfNeeded()
        XCTAssertNotNil(list.tableView.cellForRow(at: IndexPath(row: 64, section: 1)))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { window.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image); attachment.name = "synthetic-130-bottom"; attachment.lifetime = .keepAlways; add(attachment)
        list.screenFilter = .full; list.duplicatesOnly = true
        XCTAssertEqual(list.visibleClips.count, 65)
        list.selectVisible()
        XCTAssertGreaterThanOrEqual(list.selected.count, 65)
        list.clearMemory()
        XCTAssertTrue(list.clips.isEmpty && list.selected.isEmpty)
    }

    func testGridFiltersAndHiddenSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (id, title, url, full) in [("a", "Alpha", "https://example.invalid/a", true), ("b", "Beta", "https://example.invalid/a", false), ("c", "Gamma", "https://example.invalid/a#fragment", false)] {
            let dir = root.appendingPathComponent(id + ".webclip")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let plist: [String: Any] = ["Title": title, "URL": url, "FullScreen": full]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: dir.appendingPathComponent("Info.plist"))
        }
        let list = BusinessList(mode: .clips, repository: Repository(root: root), notesLoader: { AppleNotesBatch() })
        let navigation = UINavigationController(rootViewController: list)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigation; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        list.loadViewIfNeeded(); window.setNeedsLayout(); window.layoutIfNeeded()
        await list.loadItems()
        window.layoutIfNeeded(); list.view.layoutIfNeeded()
        XCTAssertEqual(list.gridColumns, 2)
        XCTAssertEqual(list.visibleClips.count, 3)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { ctx in window.layer.render(in: ctx.cgContext) }
        let attachment = XCTAttachment(image: image); attachment.name = "synthetic-bookmark-grid"; attachment.lifetime = .keepAlways; add(attachment)
        list.selected = ["a.webclip"]
        list.screenFilter = .nonFull
        list.duplicatesOnly = true
        XCTAssertEqual(list.visibleClips.map(\.id), ["b.webclip"])
        XCTAssertTrue(list.tableView(list.tableView, titleForHeaderInSection: 1)?.contains("隐藏已选 1") == true)
        list.selectVisible()
        XCTAssertEqual(list.selected, ["a.webclip", "b.webclip"])
        list.search.searchBar.text = "Gamma"
        list.updateSearchResults(for: list.search)
        XCTAssertTrue(list.visibleClips.isEmpty)
        XCTAssertEqual(list.selected.count, 2)
        list.duplicatesOnly = false
        XCTAssertEqual(list.visibleClips.map(\.id), ["c.webclip"])
        navigation.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: list)
        XCTAssertEqual(list.gridColumns, 1)
    }
}
