import XCTest
import Darwin
@testable import WebClipManager

final class StorageAndRuntimeTests: XCTestCase {
    func testNoncontainerHomeCannotEnableFilePanels() {
        for path in ["/var/mobile", "/private/var/mobile", "/var/mobile/Documents", "/var/tmp", "/"] {
            XCTAssertFalse(AppPaths.isContainerHome(URL(fileURLWithPath: path)))
        }
        XCTAssertTrue(AppPaths.isContainerHome(URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application/6D8D4654-8F87-4A83-ACBF-784565F53848")))
    }
    func testPrepareDoesNotRebindOSEnvironment() {
        func value(_ key: String) -> String? { getenv(key).map { String(cString: $0) } }
        let home = value("HOME"), tmp = value("TMPDIR"), fixed = value("CFFIXED_USER_HOME")
        let foundationHome = NSHomeDirectory()
        _ = AppPaths.prepare()
        XCTAssertEqual(value("HOME"), home)
        XCTAssertEqual(value("TMPDIR"), tmp)
        XCTAssertEqual(value("CFFIXED_USER_HOME"), fixed)
        XCTAssertEqual(NSHomeDirectory(), foundationHome)
    }
    func testActualFoundationPathsAreAppExclusive() {
        XCTAssertTrue(AppPaths.prepare())
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
    func testRuntimeProbeEmitsJSONBooleanNotInteger() throws {
        struct Flag: Decodable { let noReportSymbolAvailable: Bool }
        // JSONDecoder rejects 0/1 for Bool: ObjC comparison boxing must use @YES/@NO.
        let report = try XCTUnwrap(RuntimePermissions.capture(), "Runtime probe must decode its Boolean flag")
        _ = try JSONDecoder().decode(Flag.self, from: JSONEncoder().encode(report))
    }
    func testRuntimeUsesActualSelfAndOnlyWhitelistedValues() throws {
        let report = try XCTUnwrap(RuntimePermissions.capture())
        XCTAssertTrue(["available", "unknown"].contains(report.entitlementAPI))
        XCTAssertTrue(["available", "unknown"].contains(report.sandboxAPI))
        XCTAssertEqual(report.entitlements.count, 9)
        XCTAssertEqual(report.sandboxFilterType & 1, 1)
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
