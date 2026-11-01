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
    @MainActor func testNotesDeviceReadIsExplicitlyUnavailable() async {
        let model = NotesModel()
        await model.loadAppleNotes()
        XCTAssertTrue(model.notes.isEmpty)
        XCTAssertTrue(model.status.contains("尚未接通"))
    }
}
