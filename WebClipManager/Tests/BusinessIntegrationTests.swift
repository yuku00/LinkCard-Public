import XCTest
import UIKit
import SQLite3
import Darwin
@testable import WebClipManager

final class BusinessIntegrationTests: XCTestCase {
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @MainActor
    func testRealApplicationUsesUIKitSceneRoot() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let delegate = try XCTUnwrap(scene.delegate as? BusinessSceneDelegate)
        let window = try XCTUnwrap(delegate.window)
        let root = try XCTUnwrap(window.rootViewController as? BusinessTabs)
        XCTAssertFalse(window.isHidden)
        XCTAssertEqual(root.viewControllers?.count, 2)
        for (index, nav) in (root.viewControllers ?? []).enumerated() {
            let list = try XCTUnwrap((nav as? UINavigationController)?.topViewController as? BusinessList)
            list.loadViewIfNeeded()
            if index == 0 {
                XCTAssertTrue(["notRead", "reading", "loaded", "partial", "failed"].contains(list.readState))
                XCTAssertTrue(list.notes.isEmpty)
            } else {
                XCTAssertEqual(list.readState, "notRead")
                XCTAssertTrue(list.clips.isEmpty && list.notes.isEmpty)
            }
        }
    }
    @MainActor
    func testCompleteUIKitScanSelectionAndBackup() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let clip = root.appendingPathComponent("fixture.webclip")
        try FileManager.default.createDirectory(at: clip, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["Title": "Synthetic Bookmark", "URL": "https://example.invalid/fixture"], format: .binary, options: 0)
        try data.write(to: clip.appendingPathComponent("Info.plist"))
        let tabs = BusinessTabs(repository: Repository(root: root), notesLoader: { AppleNotesBatch() })
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = tabs; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let list = try XCTUnwrap((tabs.viewControllers?.first as? UINavigationController)?.topViewController as? BusinessList)
        list.loadViewIfNeeded()
        XCTAssertEqual(list.readState, "notRead")
        await list.loadItems() // same async handler invoked after the real confirmation action
        XCTAssertEqual(list.readState, "loaded")
        XCTAssertEqual(list.clips.count, 1)
        let row = try XCTUnwrap(list.tableView(list.tableView, cellForRowAt: IndexPath(row: 0, section: 1)) as? ClipGridRow)
        let grid = row.grid
        let cell = list.collectionView(grid, cellForItemAt: IndexPath(item: 0, section: 0)) as? ClipGridCell
        XCTAssertNotNil(cell?.iconView.image) // Missing icon uses a placeholder.
        list.collectionView(grid, didSelectItemAt: IndexPath(item: 0, section: 0))
        XCTAssertEqual(list.selected, ["fixture.webclip"])
        let stage = try await list.prepareExport(markdown: false)
        XCTAssertEqual(stage.urls.count, 1)
        XCTAssertFalse(try Data(contentsOf: stage.urls[0]).isEmpty)
        stage.clear()
        XCTAssertEqual(try Data(contentsOf: clip.appendingPathComponent("Info.plist")), data)
        tabs.selectedIndex = 1
        XCTAssertTrue((tabs.selectedViewController as? UINavigationController)?.topViewController is BusinessList)
    }
    @MainActor
    func testNotesLocateSnapshotDecodeDisplayAndTextExport() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let group = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        let metadata = try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": "group.com.apple.notes"], format: .binary, options: 0)
        try metadata.write(to: group.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist"))
        let path = group.appendingPathComponent("NoteStore.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let gzip = Data(base64Encoded: "H4sIAAAAAAACAwEnANj/EiUQABohEh/lkIjmiJDmraPmlocK56ys5LqM6KGMIPCfmIAK77+82RftgicAAAA=")!
        let expectedBody = "合成正文\n第二行 😀\n\u{FFFC}"
        let hex = gzip.map { String(format: "%02x", $0) }.joined()
        let sql = "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER, ZTITLE1 TEXT, ZISPASSWORDPROTECTED INTEGER); CREATE TABLE ZICNOTEDATA (ZNOTE INTEGER, ZDATA BLOB); INSERT INTO ZICCLOUDSYNCINGOBJECT VALUES (1,'Synthetic Note',0),(2,'Locked',1); INSERT INTO ZICNOTEDATA VALUES (1,X'\(hex)'),(2,X'\(hex)');"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        let before = try Data(contentsOf: path)
        let wal = URL(fileURLWithPath: path.path + "-wal")
        let walBefore = try Data(contentsOf: wal)
        let list = BusinessList(mode: .notes, repository: Repository(root: root), notesLoader: {
            try AppleNotesStore.read(database: AppleNotesStore.locate(in: root))
        })
        list.loadViewIfNeeded()
        await list.loadItems()
        XCTAssertEqual(list.readState, "loaded")
        XCTAssertEqual(list.notes.count, 1)
        XCTAssertTrue(list.status.contains("锁定跳过 1"))
        let cell = list.tableView(list.tableView, cellForRowAt: IndexPath(row: 0, section: 1))
        XCTAssertEqual((cell as? GlassCell)?.titleLabel.text, "Synthetic Note")
        for markdown in [false, true] {
            let stage = try await list.prepareExport(markdown: markdown)
            XCTAssertEqual(stage.urls[0].pathExtension, markdown ? "md" : "txt")
            XCTAssertEqual(try String(contentsOf: stage.urls[0], encoding: .utf8), expectedBody)
            stage.clear()
        }
        XCTAssertEqual(try Data(contentsOf: path), before)
        XCTAssertEqual(try Data(contentsOf: wal), walBefore)
    }
    @MainActor
    func testMissingReadRootIsFailureNotEmptySuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let list = BusinessList(mode: .clips, repository: Repository(root: root), notesLoader: { AppleNotesBatch() })
        list.loadViewIfNeeded()
        await list.loadItems()
        XCTAssertEqual(list.readState, "failed")
        XCTAssertFalse(list.busy)
        XCTAssertTrue(list.clips.isEmpty)
    }
    func testExportPermissionsTraversalAndCleanup() throws {
        let stage = try ExportStaging()
        let parent = stage.directory
        var info = stat()
        XCTAssertEqual(lstat(parent.path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o700)
        for name in ["../outside", ".", "..", "/absolute", "a/b", "a\\b"] {
            XCTAssertThrowsError(try stage.write(Data(), name: name))
        }
        let url = try stage.write(Data("synthetic".utf8), name: "note.txt")
        XCTAssertEqual(lstat(url.path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o600)
        XCTAssertThrowsError(try stage.write(Data(), name: "note.txt"))
        stage.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.path))
    }
}
