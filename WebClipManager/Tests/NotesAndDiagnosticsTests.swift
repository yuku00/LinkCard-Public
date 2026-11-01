import XCTest
@testable import WebClipManager

final class NotesAndDiagnosticsTests: XCTestCase {
    func testUTF8BodyRoundTripAndBOM() throws {
        let body = "第一行\n\n- 第二行 😀\n"
        XCTAssertEqual(try NoteFiles.decode(Data(body.utf8)), body)
        XCTAssertEqual(try NoteFiles.decode(Data(("\u{FEFF}" + body).utf8)), body)
        XCTAssertEqual(try NoteFiles.decode(Data()), "")
        XCTAssertThrowsError(try NoteFiles.decode(Data([0xFF, 0xFE])))
        XCTAssertThrowsError(try NoteFiles.decode(Data("a\0b".utf8)))
        XCTAssertThrowsError(try NoteFiles.decode(Data(repeating: 65, count: NoteFiles.fileLimit + 1)))
    }
    func testNamesCannotEscapeAndDuplicatesStayDistinct() {
        let a = NoteFiles.filename("../a\\b:\n", index: 0, markdown: true)
        let b = NoteFiles.filename("../a\\b:\n", index: 1, markdown: true)
        XCTAssertFalse(a.contains("/")); XCTAssertFalse(a.contains("\\")); XCTAssertFalse(a.contains("\n"))
        XCTAssertTrue(a.hasSuffix(".md")); XCTAssertNotEqual(a, b)
        XCTAssertEqual(NoteFiles.filename("", index: 0, markdown: false), "001-备忘录.txt")
    }
    func testReadOnlyFileImport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("synthetic.md")
        let body = Data("# Synthetic\n\nBody, not only a title.\n".utf8)
        try body.write(to: file)
        XCTAssertEqual(try NoteFiles.read(file).text, String(data: body, encoding: .utf8))
        XCTAssertEqual(try Data(contentsOf: file), body)
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try NoteFiles.read(link))
    }
    func testDiagnosticWhitelistAndRedaction() throws {
        let report = DiagnosticReport.capture(readState: "SECRET-TITLE-URL", osVersion: "16.6")
        let data = try report.encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["schemaVersion", "osVersion", "webClipsReadState", "uiWebClipClassPresent", "selectorPresence", "deletionEnabled"]))
        XCTAssertEqual(report.webClipsReadState, "notRead")
        XCTAssertFalse(report.deletionEnabled)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("SECRET"))
        XCTAssertEqual(report.selectorPresence.count, 3)
    }
}
