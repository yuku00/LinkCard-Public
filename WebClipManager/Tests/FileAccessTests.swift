import XCTest
import Darwin
@testable import WebClipManager

final class FileAccessTests: XCTestCase {
    func testPOSIXReadAndNoFollow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fd = try ReadAccess.openDirectory(root.path)
        close(fd)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try ReadAccess.openDirectory(link.path))
        do {
            _ = try ReadAccess.openDirectory(root.appendingPathComponent("missing").path)
            XCTFail("Missing directory must throw")
        } catch {
            let safe = AccessError.capture(error)
            XCTAssertEqual(safe.domain, NSPOSIXErrorDomain)
            XCTAssertEqual(safe.underlyingPOSIX, Int(ENOENT))
            XCTAssertEqual(safe.category, "notFound")
        }
    }
    func testNestedErrorRedactionAndClassification() throws {
        let secret = "SECRET-TITLE-URL"
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES), userInfo: [NSFilePathErrorKey: secret])
        let error = NSError(domain: NSCocoaErrorDomain, code: 257,
            userInfo: [NSUnderlyingErrorKey: posix, NSLocalizedDescriptionKey: secret])
        let safe = AccessError.capture(error)
        XCTAssertEqual(safe.domain, NSCocoaErrorDomain)
        XCTAssertEqual(safe.code, 257)
        XCTAssertEqual(safe.underlyingPOSIX, Int(EACCES))
        XCTAssertEqual(safe.category, "accessDeniedCauseUndetermined")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(safe), as: UTF8.self).contains(secret))
        XCTAssertEqual(AccessError.capture(NSError(domain: secret, code: 9)).domain, "other")
        XCTAssertEqual(AccessError.capture(NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))).category, "operationNotPermittedCauseUndetermined")
        XCTAssertEqual(AccessError.capture(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTDIR))).category, "notDirectory")
    }
    func testProbeNeverExportsArbitraryResolvedPath() throws {
        let snapshot = ReadAccess.diagnostics()
        XCTAssertEqual(snapshot.paths.count, ReadAccess.diagnosticPaths.count)
        for item in snapshot.paths {
            XCTAssertTrue(ReadAccess.diagnosticPaths.contains(item.path))
            XCTAssertTrue(item.resolvedPath == nil || item.resolvedPath == "redacted" || ReadAccess.diagnosticPaths.contains(item.resolvedPath!))
            XCTAssertEqual(item.openSucceeded, item.openErrno == 0)
        }
    }
}
