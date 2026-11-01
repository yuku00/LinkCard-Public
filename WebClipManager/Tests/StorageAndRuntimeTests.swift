import XCTest
import Darwin
@testable import WebClipManager

final class StorageAndRuntimeTests: XCTestCase {
    func testActualFoundationPathsAreAppExclusive() {
        XCTAssertTrue(AppPaths.ready)
        let paths = LocalPathDiagnostics.capture()
        XCTAssertTrue(paths.homeMatches)
        XCTAssertTrue(paths.documentsMatch)
        XCTAssertTrue(paths.temporaryMatches)
        XCTAssertNotEqual(AppPaths.documents.path, "/var/mobile/Documents")
        XCTAssertNotEqual(AppPaths.temporary.path, "/var/tmp")
    }
    func testOwnedPathRejectsSharedPrefixEscapeAndSymlink() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        XCTAssertTrue(AppPaths.isOwnedPath(base.appendingPathComponent("Documents/test.log"), root: base))
        for path in ["/var/mobile/Documents/a", "/var/tmp/a", base.path + "-other/a", base.path + "/../escape"] {
            XCTAssertFalse(AppPaths.isOwnedPath(URL(fileURLWithPath: path), root: base))
        }
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: base.deletingLastPathComponent())
        XCTAssertFalse(AppPaths.isOwnedPath(link.appendingPathComponent("secret"), root: base))
    }
    func testRuntimeUsesActualSelfAndOnlyWhitelistedValues() throws {
        let report = try XCTUnwrap(RuntimePermissions.capture())
        XCTAssertTrue(["available", "unknown"].contains(report.entitlementAPI))
        XCTAssertTrue(["available", "unknown"].contains(report.sandboxAPI))
        XCTAssertEqual(report.entitlements.count, 9)
        XCTAssertEqual(Set(report.entitlements.keys), Set(report.expectedComparison.keys))
        for value in report.entitlements.values {
            XCTAssertTrue(["unknown", "absent", "boolean:true", "boolean:false", "string:org.example.WebClipManager", "string:redacted", "unexpected-type"].contains(value))
        }
        for value in report.expectedComparison.values { XCTAssertTrue(["match", "mismatch", "unknown"].contains(value)) }
        XCTAssertEqual(report.sandboxChecks.count, 6)
        // Simulator signature is not the TrollStore signature: never force a match
        // or use these tests as evidence that installed device access succeeds.
        XCTAssertFalse(LocalPathDiagnostics.capture().applicationUsesUserDefaults)
    }
    func testNotesErrorsAndStartupExportCannotLeakUserContent() throws {
        NotesReadDiagnostic.record(state: "failed", error: NSError(domain: NSCocoaErrorDomain, code: 257, userInfo: [NSLocalizedDescriptionKey: "PRIVATE-NOTE", NSFilePathErrorKey: "PRIVATE-NOTE", NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))]))
        let report = NotesReadDiagnostic.capture()
        XCTAssertEqual(report.failure?.underlyingPOSIX, Int(EPERM))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(report), as: UTF8.self).contains("PRIVATE-NOTE"))
        NotesReadDiagnostic.record(state: "notRead")
        StartupLog.record("PRIVATE-NOTE")
        XCTAssertFalse(StartupLog.exportText.contains("PRIVATE-NOTE"))
        StartupLog.record("S0_MAIN")
        XCTAssertTrue(StartupLog.exportText.contains("S0_MAIN"))
    }
}
