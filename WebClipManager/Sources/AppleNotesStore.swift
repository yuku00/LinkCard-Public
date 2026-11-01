import Foundation
import SQLite3

struct AppleNotesBatch: Sendable {
    var notes: [ImportedNote] = []
    var locked = 0
    var deleted = 0
    var unavailable = 0
    var unsupported = 0
    var incomplete = 0
    var limited = false
    var summary: String {
        "读取 \(notes.count) 篇 · 锁定跳过 \(locked) · 删除标记跳过 \(deleted) · 未下载 \(unavailable) · 无法解析 \(unsupported) · 含未导出嵌入内容 \(incomplete)" + (limited ? "；达到批次限制，其余未读取" : "")
    }
}

// No writes to Notes: source is READONLY; SQLite backup destination is memory only.
enum AppleNotesStore {
    static let snapshotLimit = 128 * 1024 * 1024
    static let groupID = "group.com.apple.notes"

    static func regularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else {
            throw ClipError.invalid("备忘录文件类型不安全")
        }
    }

    static func locate(in root: URL = URL(fileURLWithPath: "/var/mobile/Containers/Shared/AppGroup")) throws -> URL {
        let fm = FileManager.default
        let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        var candidates: [URL] = []
        for child in children {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let metadata = child.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard (try? regularFile(metadata)) != nil,
                  let size = try? metadata.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 1024 * 1024,
                  let data = try? Data(contentsOf: metadata),
                  let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dict = object as? [String: Any],
                  dict["MCMMetadataIdentifier"] as? String == groupID else { continue }
            let database = child.appendingPathComponent("NoteStore.sqlite")
            try regularFile(database)
            candidates.append(database)
        }
        guard candidates.count == 1 else {
            throw ClipError.invalid(candidates.isEmpty ? "未找到可读 Notes AppGroup；检查 TrollStore 权限及备忘录是否已初始化" : "发现多个 Notes 数据库，已停止以免选错")
        }
        return candidates[0]
    }

    static func load() throws -> AppleNotesBatch { try read(database: locate()) }

    static func read(database: URL) throws -> AppleNotesBatch {
        try regularFile(database)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: database.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) { try regularFile(sidecar) }
        }
        var source: OpaquePointer?
        guard sqlite3_open_v2(database.path, &source, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let source = source { sqlite3_close(source) }
            throw ClipError.invalid("无法只读打开 Notes；权限不足、设备锁定或 WAL 不可读")
        }
        defer { sqlite3_close(source) }
        sqlite3_busy_timeout(source, 250)
        // Establish a read transaction before sizing and backing up, so WAL changes cannot restart the snapshot.
        guard sqlite3_exec(source, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw ClipError.invalid("无法开始只读快照") }
        defer { sqlite3_exec(source, "ROLLBACK", nil, nil, nil) }
        let pages = try scalar(source, "PRAGMA page_count")
        let pageSize = try scalar(source, "PRAGMA page_size")
        guard pages >= 0, pageSize > 0, pages <= Int64(snapshotLimit) / pageSize else {
            throw ClipError.invalid("Notes 数据库超过 128 MiB 快照限制；未导出")
        }
        var memory: OpaquePointer?
        guard sqlite3_open_v2(":memory:", &memory, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let memory = memory { sqlite3_close(memory) }
            throw ClipError.invalid("无法创建内存快照")
        }
        defer { sqlite3_close(memory) }
        guard let backup = sqlite3_backup_init(memory, "main", source, "main") else { throw ClipError.invalid("SQLite backup 初始化失败") }
        var code: Int32 = SQLITE_OK
        let deadline = Date().addingTimeInterval(10)
        repeat {
            code = sqlite3_backup_step(backup, 128)
        } while code == SQLITE_OK && Date() < deadline
        let finish = sqlite3_backup_finish(backup)
        guard code == SQLITE_DONE, finish == SQLITE_OK else {
            throw ClipError.invalid("快照未完成（数据库忙、变化或超时）；没有使用不完整副本")
        }
        guard sqlite3_exec(memory, "PRAGMA temp_store=MEMORY; PRAGMA query_only=ON", nil, nil, nil) == SQLITE_OK else { throw ClipError.invalid("无法限制快照为只读") }
        return try extract(memory)
    }

    static func scalar(_ db: OpaquePointer?, _ sql: String) throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ClipError.invalid("数据库结构不支持") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw ClipError.invalid("无法读取数据库结构") }
        return sqlite3_column_int64(statement, 0)
    }

    static func columns(_ db: OpaquePointer?, _ table: String) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else { throw ClipError.invalid("无法检查 Notes 结构") }
        defer { sqlite3_finalize(statement) }
        var result: Set<String> = []
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 1) { result.insert(String(cString: text)) }
            code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw ClipError.invalid("无法检查 Notes 结构") }
        return result
    }

    static func extract(_ db: OpaquePointer?) throws -> AppleNotesBatch {
        let objects = try columns(db, "ZICCLOUDSYNCINGOBJECT")
        let bodies = try columns(db, "ZICNOTEDATA")
        guard Set(["Z_PK", "ZTITLE1", "ZISPASSWORDPROTECTED"]).isSubset(of: objects),
              Set(["ZNOTE", "ZDATA"]).isSubset(of: bodies) else {
            throw ClipError.invalid("不是支持的 iOS 16 Notes 结构；未尝试猜测锁定状态")
        }
        let deleted = objects.contains("ZMARKEDFORDELETION") ? "COALESCE(o.ZMARKEDFORDELETION,0)" : "0"
        var protected = "COALESCE(o.ZISPASSWORDPROTECTED,0) != 0"
        for field in ["ZCRYPTOINITIALIZATIONVECTOR", "ZCRYPTOTAG"] where bodies.contains(field) {
            protected += " OR d.\(field) IS NOT NULL"
        }
        // Do not even retrieve title/body for protected rows. Never use snippets as a fallback body.
        let sql = """
        SELECT CASE WHEN \(protected) THEN '' ELSE substr(o.ZTITLE1,1,256) END,
          (\(protected)), \(deleted), length(d.ZDATA),
          CASE WHEN (\(protected)) OR \(deleted) != 0 OR length(d.ZDATA) > \(AppleNoteBody.limit)
               THEN NULL ELSE d.ZDATA END
        FROM ZICCLOUDSYNCINGOBJECT o JOIN ZICNOTEDATA d ON d.ZNOTE = o.Z_PK
        ORDER BY o.Z_PK LIMIT 10001
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ClipError.invalid("Notes 查询不兼容") }
        defer { sqlite3_finalize(statement) }
        var result = AppleNotesBatch()
        var total = 0
        var rows = 0
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            rows += 1
            if rows > 10000 || result.notes.count >= 1000 { result.limited = true; break }
            if sqlite3_column_int(statement, 1) != 0 { result.locked += 1 }
            else if sqlite3_column_int(statement, 2) != 0 { result.deleted += 1 }
            else if sqlite3_column_type(statement, 3) == SQLITE_NULL || sqlite3_column_int64(statement, 3) == 0 { result.unavailable += 1 }
            else if sqlite3_column_int64(statement, 3) > Int64(AppleNoteBody.limit) { result.unsupported += 1 }
            else if let blob = sqlite3_column_blob(statement, 4) {
                do {
                    let text = try AppleNoteBody.decode(Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 4))))
                    guard total + text.utf8.count <= NoteFiles.totalLimit else { result.limited = true; break }
                    total += text.utf8.count
                    let title = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "未命名备忘录"
                    result.notes.append(ImportedNote(title: title.isEmpty ? "未命名备忘录" : title, text: text))
                    if text.contains("\u{FFFC}") { result.incomplete += 1 }
                } catch { result.unsupported += 1 }
            } else { result.unsupported += 1 }
            code = sqlite3_step(statement)
        }
        guard result.limited || code == SQLITE_DONE else { throw ClipError.invalid("读取 Notes 快照失败；当前批次未替换") }
        return result
    }
}
