import XCTest
import Foundation
@testable import WebClipManager

final class BackgroundStoreTests: XCTestCase {
    private func withParent(_ body: (URL, BackgroundStore) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let parent = base.appendingPathComponent("background-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: parent) }
        try body(parent, BackgroundStore(parent: parent))
    }
    func testMissingApplicationSupportIsCreatedOnlyOnSave() throws {
        try withParent { base, _ in
            let support = base.appendingPathComponent("Application Support")
            let store = BackgroundStore(parent: support)
            XCTAssertNil(try store.load())
            try store.reset()
            XCTAssertFalse(FileManager.default.fileExists(atPath: support.path))
            let data = Data("synthetic image".utf8)
            try store.save(data)
            XCTAssertEqual(try BackgroundStore(parent: support).load(), data)
        }
    }
    func testRestartResetAndFailedCommit() throws {
        try withParent { parent, store in
            let first = Data("synthetic old image".utf8), second = Data("synthetic new image".utf8)
            try store.save(first)
            XCTAssertEqual(try BackgroundStore(parent: parent).load(), first)
            XCTAssertThrowsError(try store.save(second, beforeCommit: { throw NSError(domain: "injected", code: 1) }))
            XCTAssertEqual(try BackgroundStore(parent: parent).load(), first)
            try store.reset()
            XCTAssertNil(try BackgroundStore(parent: parent).load())
        }
    }
    func testKnownSystemVarAliasAndHostileAncestor() throws {
        XCTAssertEqual(BackgroundStore.normalizeSystemVar(URL(fileURLWithPath: "/var/mobile/Library/Application Support")).path, "/private/var/mobile/Library/Application Support")
        XCTAssertEqual(BackgroundStore.normalizeSystemVar(URL(fileURLWithPath: "/various/Library")).path, "/various/Library")
        try withParent { parent, _ in
            let target = parent.appendingPathComponent("target")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let link = parent.appendingPathComponent("untrusted")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let store = BackgroundStore(parent: link.appendingPathComponent("Application Support"))
            XCTAssertThrowsError(try store.save(Data("image".utf8)))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        }
    }
    func testSymlinkDirectoryIsRejected() throws {
        try withParent { parent, store in
            let target = parent.appendingPathComponent("other")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(at: parent.appendingPathComponent("org.example.WebClipManager.background"), withDestinationURL: target)
            XCTAssertThrowsError(try store.save(Data("x".utf8)))
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.reset())
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
        }
    }
    func testSymlinkLeafAndUnsafeDirectoryAreRejected() throws {
        try withParent { parent, store in
            let dir = parent.appendingPathComponent("org.example.WebClipManager.background")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let target = parent.appendingPathComponent("unrelated")
            let original = Data("keep".utf8); try original.write(to: target)
            try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("background.jpg"), withDestinationURL: target)
            XCTAssertThrowsError(try store.save(Data("new".utf8)))
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.reset())
            XCTAssertEqual(try Data(contentsOf: target), original)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            XCTAssertThrowsError(try store.load())
        }
    }
}
