import XCTest
import SQLite3
@testable import WebClipManager

final class AppleNotesTests: XCTestCase {
    // Generated locally from invented text, not an Apple database or upstream user fixture.
    let gzip = Data(base64Encoded: "H4sIAAAAAAACAwEnANj/EiUQABohEh/lkIjmiJDmraPmlocK56ys5LqM6KGMIPCfmIAK77+82RftgicAAAA=")!
    let body = "合成正文\n第二行 😀\n\u{FFFC}"

    func testGzipProtobufBodyAndMalformedData() throws {
        XCTAssertEqual(try AppleNoteBody.decode(gzip), body)
        XCTAssertThrowsError(try AppleNoteBody.decode(Data(gzip.dropLast())))
        var corrupt = gzip; corrupt[corrupt.count - 5] ^= 0xff
        XCTAssertThrowsError(try AppleNoteBody.decode(corrupt))
        XCTAssertThrowsError(try AppleNoteBody.decode(Data([0x12, 0x00])))
        XCTAssertThrowsError(try AppleNoteBody.field(2, in: Data([0x12, 0x80])))
        XCTAssertThrowsError(try AppleNoteBody.field(2, in: Data([0x12, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x02])))
        XCTAssertThrowsError(try AppleNoteBody.field(2, in: Data([0x00])))
        XCTAssertThrowsError(try AppleNoteBody.field(2, in: Data([0x12, 0x00, 0x12, 0x00])))
        XCTAssertEqual(try AppleNoteBody.field(2, in: Data([0x08, 0x01, 0x12, 0x00, 0x25, 1, 2, 3, 4])), Data())
    }

    func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func execute(_ db: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "SyntheticSQL", code: 1)
        }
    }

    func testWALSnapshotFilteringAndSourceUnchanged() throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("NoteStore.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        try execute(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;")
        try execute(db, "CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER PRIMARY KEY, ZTITLE1 TEXT, ZISPASSWORDPROTECTED INTEGER, ZMARKEDFORDELETION INTEGER);")
        try execute(db, "CREATE TABLE ZICNOTEDATA (ZNOTE INTEGER, ZDATA BLOB, ZCRYPTOTAG BLOB);")
        let hex = gzip.map { String(format: "%02x", $0) }.joined()
        try execute(db, "INSERT INTO ZICCLOUDSYNCINGOBJECT VALUES (1,'Synthetic',0,0),(2,'Locked',1,0),(3,'Deleted',0,1),(4,'Missing',0,0),(5,'Broken',0,0),(6,'Encrypted',0,0);")
        try execute(db, "INSERT INTO ZICNOTEDATA VALUES (1,X'\(hex)',NULL),(2,X'\(hex)',NULL),(3,X'\(hex)',NULL),(4,NULL,NULL),(5,X'0102',NULL),(6,X'\(hex)',X'01');")
        let originalDB = try Data(contentsOf: path)
        let wal = URL(fileURLWithPath: path.path + "-wal")
        let originalWAL = try Data(contentsOf: wal)
        let batch = try AppleNotesStore.read(database: path)
        XCTAssertEqual(batch.notes.count, 1)
        XCTAssertEqual(batch.notes.first?.text, body)
        XCTAssertEqual(batch.locked, 2)
        XCTAssertEqual(batch.deleted, 1)
        XCTAssertEqual(batch.unavailable, 1)
        XCTAssertEqual(batch.unsupported, 1)
        XCTAssertEqual(batch.incomplete, 1)
        XCTAssertFalse(batch.limited)
        XCTAssertEqual(try Data(contentsOf: path), originalDB)
        XCTAssertEqual(try Data(contentsOf: wal), originalWAL)
    }

    func testContainerIdentityAndSymlinkRefusal() throws {
        let root = try temp()
        defer { try? FileManager.default.removeItem(at: root) }
        let group = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        let metadata = group.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: ["MCMMetadataIdentifier": "group.com.apple.notes"], format: .binary, options: 0)
        try data.write(to: metadata)
        let database = group.appendingPathComponent("NoteStore.sqlite")
        try Data().write(to: database)
        XCTAssertEqual(try AppleNotesStore.locate(in: root), database)
        try FileManager.default.removeItem(at: database)
        try FileManager.default.createSymbolicLink(at: database, withDestinationURL: metadata)
        XCTAssertThrowsError(try AppleNotesStore.locate(in: root))
    }

    func testMissingProtectionColumnFailsClosed() throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(":memory:", &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        try execute(db, "CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER, ZTITLE1 TEXT); CREATE TABLE ZICNOTEDATA (ZNOTE INTEGER, ZDATA BLOB);")
        XCTAssertThrowsError(try AppleNotesStore.extract(db))
    }
}
