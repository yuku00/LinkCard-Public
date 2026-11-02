import XCTest
import Foundation
@testable import WebClipManager

private class DeleteMock: NSObject {
    static var root = ""
    static var selected = "A.webclip"
    static var pathOverride: String?
    static var blocked = false
    static var calls = 0
    @objc class func webClipWithIdentifier(_ id: NSString) -> AnyObject { DeleteMock() }
    @objc class func pathForWebClipWithIdentifier(_ id: NSString) -> NSString { (pathOverride ?? (root as NSString).appendingPathComponent(id as String)) as NSString }
    @objc func identifier() -> NSString { DeleteMock.selected as NSString }
    @objc func removalDisallowed() -> Bool { DeleteMock.blocked }
    @objc func removeFromDisk() -> Bool { DeleteMock.calls += 1; return true }
}
private class BadABI: NSObject {
    @objc class func webClipWithIdentifier(_ id: NSString) -> AnyObject { BadABI() }
    @objc class func pathForWebClipWithIdentifier(_ id: NSString) -> NSString { "" }
    @objc func identifier() -> NSString { "A.webclip" }
    @objc func removalDisallowed() -> Bool { false }
    @objc func removeFromDisk(_ unexpected: Int) -> Bool { true }
}
final class ExperimentalDeleteTests: XCTestCase {
    private var root = ""
    private let id = "A.webclip"
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: root + "/" + id, withIntermediateDirectories: true)
        DeleteMock.root = root; DeleteMock.selected = id; DeleteMock.pathOverride = nil; DeleteMock.blocked = false; DeleteMock.calls = 0
        try plist(["Title": "WCM-DELETE-TEST", "ConfigurationIsManaged": false, "RemovalDisallowed": false])
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(atPath: root) }
    private func plist(_ value: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: root + "/" + id + "/Info.plist"))
    }
    private func run(_ cls: AnyClass = DeleteMock.self) -> [AnyHashable: Any] {
        WCMExperimentalDeleteForTesting(id, root, cls)
    }
    func testOneCallAndPostcondition() {
        let r = run(); XCTAssertEqual(r["called"] as? Bool, true); XCTAssertEqual(r["returned"] as? Bool, true)
        XCTAssertEqual(r["source"] as? String, "仍存在"); XCTAssertEqual(DeleteMock.calls, 1)
    }
    func testWrongABIPathIdentifierAndRuntimeManagedRefuse() {
        XCTAssertEqual(run(BadABI.self)["called"] as? Bool, false)
        DeleteMock.pathOverride = root + "/other.webclip"; XCTAssertEqual(run()["called"] as? Bool, false)
        DeleteMock.pathOverride = nil; DeleteMock.selected = "other.webclip"; XCTAssertEqual(run()["called"] as? Bool, false)
        DeleteMock.selected = id; DeleteMock.blocked = true; XCTAssertEqual(run()["called"] as? Bool, false)
        XCTAssertEqual(DeleteMock.calls, 0)
    }
    func testUnknownAndManagedPlistRefuse() throws {
        let cases: [[String: Any]] = [
            ["Title":"WCM-DELETE-TEST", "RemovalDisallowed":false],
            ["Title":"WCM-DELETE-TEST", "ConfigurationIsManaged":true, "RemovalDisallowed":false],
            ["Title":"WCM-DELETE-TEST", "ConfigurationIsManaged":false, "RemovalDisallowed":1],
            ["Title":"other", "ConfigurationIsManaged":false, "RemovalDisallowed":false]
        ]
        for p in cases { try plist(p); XCTAssertEqual(run()["called"] as? Bool, false) }
        XCTAssertEqual(DeleteMock.calls, 0)
    }
    func testSymlinkRefused() throws {
        try FileManager.default.moveItem(atPath: root + "/" + id, toPath: root + "/real")
        try FileManager.default.createSymbolicLink(atPath: root + "/" + id, withDestinationPath: root + "/real")
        XCTAssertEqual(run()["called"] as? Bool, false); XCTAssertEqual(DeleteMock.calls, 0)
    }
    func testCancellationAndBackupFailureNeverCallBridge() throws {
        let clip = Clip(id: id, title: "WCM-DELETE-TEST", url: "", fullScreen: false, removalDisallowed: false, icon: nil)
        var backups = 0, calls = 0
        let backup: (Clip) throws -> Void = { _ in backups += 1 }
        let bridge: (String) -> [AnyHashable: Any] = { _ in calls += 1; return ["called": true, "returned": true] }
        _ = try ExperimentalDelete.run(clip, firstConfirmed: false, secondConfirmed: true, backup: backup, bridge: bridge)
        _ = try ExperimentalDelete.run(clip, firstConfirmed: true, secondConfirmed: false, backup: backup, bridge: bridge)
        XCTAssertEqual(backups, 0); XCTAssertEqual(calls, 0)
        XCTAssertThrowsError(try ExperimentalDelete.run(clip, firstConfirmed: true, secondConfirmed: true, backup: { _ in throw ClipError.invalid("no backup") }, bridge: bridge))
        XCTAssertEqual(calls, 0)
        _ = try ExperimentalDelete.run(clip, firstConfirmed: true, secondConfirmed: true, backup: backup, bridge: bridge)
        XCTAssertEqual(backups, 1); XCTAssertEqual(calls, 1)
    }
}
