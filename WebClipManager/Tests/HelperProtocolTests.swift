import XCTest
@testable import WebClipManager
final class HelperProtocolTests: XCTestCase {
    func testSuccessAndProtocolRejections() throws {
        let valid = #"{"version":1,"errno":0,"clips":[{"id":"demo.webclip","title":"Synthetic","url":"https://example.invalid","fullScreen":false,"removalDisallowed":false}],"skipped":0}"#
        let result = try HelperReader.decode(Data(valid.utf8))
        XCTAssertEqual(result.clips.count, 1)
        XCTAssertEqual(result.clips[0].title, "Synthetic")
        for invalid in ["{}", "not-json", valid.replacingOccurrences(of: "demo.webclip", with: "../demo.webclip"), valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":2"), valid.replacingOccurrences(of: "\"errno\":0", with: "\"errno\":1")] {
            XCTAssertThrowsError(try HelperReader.decode(Data(invalid.utf8)))
        }
        XCTAssertThrowsError(try HelperReader.decode(Data(repeating: 65, count: 8 * 1024 * 1024 + 1)))
    }
    func testSpawnErrorRetainsNativeCodeAndInvalidExit() throws {
        let error = NSError(domain: NSPOSIXErrorDomain, code: 1, userInfo: [
            "operation": "helperTransport", "helperStage": "spawn", "helperSpawned": false,
            "helperStatusValid": false, "helperExit": 0, "helperWaitErrno": 0])
        let captured = AccessError.capture(error)
        XCTAssertEqual(captured.domain, NSPOSIXErrorDomain)
        XCTAssertEqual(captured.code, 1)
        XCTAssertEqual(captured.underlyingPOSIX, 1)
        XCTAssertEqual(captured.operation, "helperTransport")
        XCTAssertEqual(captured.helperStage, "spawn")
        XCTAssertEqual(captured.helperSpawned, false)
        XCTAssertEqual(captured.helperStatusValid, false)
        XCTAssertNil(captured.helperExit)
        XCTAssertTrue(captured.summary.contains("exit=unavailable"))
        let encoded = try JSONEncoder().encode(captured)
        let decoded = try JSONDecoder().decode(AccessError.self, from: encoded)
        XCTAssertEqual(decoded.helperStage, "spawn")
        XCTAssertNil(decoded.helperExit)
    }
    func testHelperReadPreservesNativeError() {
        let captured = AccessError.capture(ReadAccess.failure("helperRead", 1))
        XCTAssertEqual(captured.operation, "helperRead")
        XCTAssertEqual(captured.code, 1)
        XCTAssertNil(captured.helperStatusValid)
    }
    @MainActor func testNotesClearOnlyResetsInMemoryBatch() {
        let model = NotesModel()
        let note = ImportedNote(title: "Synthetic", text: "Fixture")
        model.notes = [note]
        model.selected = [note.id]
        model.clear()
        XCTAssertTrue(model.notes.isEmpty)
        XCTAssertTrue(model.selected.isEmpty)
        XCTAssertTrue(model.status.contains("不修改 Apple Notes"))
    }
}
