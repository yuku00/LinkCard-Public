import XCTest
@testable import WebClipManager

final class RepositoryTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func create(_ id: String, root: URL) throws {
        let dir = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist: [String: Any] = ["Title": "Synthetic test", "URL": "synthetic-value", "FullScreen": true]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: dir.appendingPathComponent("Info.plist"))
    }

    func testScanDuplicatesBackupAndRefusedDeletion() async throws {
        let root = try temporaryRoot()
        try create("first.webclip", root: root)
        try create("second.webclip", root: root)
        let repository = Repository(root: root)
        let scan = try await repository.scan()
        XCTAssertEqual(scan.clips.count, 2)
        XCTAssertTrue(scan.issues.isEmpty)
        XCTAssertTrue(scan.clips.allSatisfy(\.fullScreen))
        XCTAssertEqual(Repository.duplicateIDs(scan.clips).count, 2)
        let backup = try await repository.backup(ids: scan.clips.map(\.id))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: backup.data, format: nil) as? [String: Any])
        XCTAssertEqual((plist["entries"] as? [[String: Any]])?.count, 2)
        let before = try Data(contentsOf: root.appendingPathComponent("first.webclip/Info.plist"))
        let results = await repository.delete(ids: scan.clips.map(\.id))
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.message.hasPrefix("未删除") })
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("first.webclip/Info.plist")), before)
    }

    func testDisabledDeletionRejectsEverySyntheticTargetWithoutModifyingFiles() async throws {
        let root = try temporaryRoot()
        try create("normal.webclip", root: root)
        try create("managed.webclip", root: root)
        let managedInfo = root.appendingPathComponent("managed.webclip/Info.plist")
        let managed: [String: Any] = ["Title": "Managed fixture", "URL": "https://example.invalid", "RemovalDisallowed": true]
        try PropertyListSerialization.data(fromPropertyList: managed, format: .binary, options: 0).write(to: managedInfo)
        let normalInfo = root.appendingPathComponent("normal.webclip/Info.plist")
        let beforeNormal = try Data(contentsOf: normalInfo)
        let beforeManaged = try Data(contentsOf: managedInfo)
        let ids = ["normal.webclip", "managed.webclip", "missing.webclip", "../escape.webclip"]
        let results = await Repository(root: root).delete(ids: ids)
        XCTAssertEqual(results.map(\.id), ids.sorted())
        XCTAssertTrue(results.allSatisfy { $0.message.hasPrefix("未删除") })
        XCTAssertEqual(try Data(contentsOf: normalInfo), beforeNormal)
        XCTAssertEqual(try Data(contentsOf: managedInfo), beforeManaged)
    }

    func testMalformedAndSymlinkAreReported() async throws {
        let root = try temporaryRoot()
        try create("broken.webclip", root: root)
        try Data("not plist".utf8).write(to: root.appendingPathComponent("broken.webclip/Info.plist"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.webclip"), withDestinationURL: root)
        let scan = try await Repository(root: root).scan()
        XCTAssertTrue(scan.clips.isEmpty)
        XCTAssertEqual(scan.issues.count, 2)
    }

    func testPartialBackupDoesNotPretendAllSucceeded() async throws {
        let root = try temporaryRoot()
        try create("good.webclip", root: root)
        let backup = try await Repository(root: root).backup(ids: ["good.webclip", "../escape.webclip"])
        XCTAssertEqual(backup.results.count, 2)
        XCTAssertEqual(backup.results.filter { $0.message.hasPrefix("备份失败") }.count, 1)
    }

    func testMissingRootThrows() async throws {
        let root = try temporaryRoot().appendingPathComponent("missing")
        do {
            _ = try await Repository(root: root).scan()
            XCTFail("Missing root must not be reported as an empty successful scan")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }
}
