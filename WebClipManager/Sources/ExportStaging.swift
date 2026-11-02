import Foundation
import Darwin

// The descriptors pin our directories; cleanup never traverses a supplied URL.
final class ExportStaging {
    let directory: URL
    private let parentFD: Int32
    private let dirFD: Int32
    private let session: String
    private var owned: [String: (dev_t, ino_t)] = [:]
    private(set) var urls: [URL] = []
    private static func failure(_ stage: String, _ code: Int32 = errno) -> Error { ReadAccess.failure(stage, code) }
    private static func checkDir(_ fd: Int32, privateDir: Bool) throws {
        var s = stat()
        guard fstat(fd, &s) == 0 else { throw failure("statDirectory") }
        guard s.st_mode & S_IFMT == S_IFDIR,
              privateDir ? (s.st_uid == geteuid() && s.st_mode & 0o7777 == 0o700) : ((s.st_uid == geteuid() || s.st_uid == 0) && s.st_mode & 0o022 == 0) else {
            throw ClipError.invalid("导出目录所有者或权限不安全。")
        }
    }
    init(parent: URL? = nil) throws {
        let base = BackgroundStore.normalizeSystemVar(parent ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true))
        let verifyAncestors = parent == nil
        guard base.isFileURL, base.path.hasPrefix("/") else { throw ClipError.invalid("导出目录无效。") }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Self.failure("openDirectory") }
        do {
            if verifyAncestors { try Self.checkDir(fd, privateDir: false) }
            let components = Array(base.pathComponents.dropFirst())
            for (index, part) in components.enumerated() {
                guard part != ".", part != "..", !part.contains("/") else { throw ClipError.invalid("导出路径无效。") }
                var next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0 && errno == ENOENT && index == components.count - 1 {
                    guard mkdirat(fd, part, 0o700) == 0 || errno == EEXIST else { throw Self.failure("createParent") }
                    next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else { throw Self.failure("openDirectory") }
                close(fd); fd = next
                if verifyAncestors { try Self.checkDir(fd, privateDir: false) }
            }
            if !verifyAncestors { try Self.checkDir(fd, privateDir: true) }
            let store = "org.example.WebClipManager.export"
            if mkdirat(fd, store, 0o700) != 0 && errno != EEXIST { throw Self.failure("createStore") }
            let storeFD = openat(fd, store, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard storeFD >= 0 else { throw Self.failure("openStore") }
            close(fd); fd = storeFD
            try Self.checkDir(fd, privateDir: true)
            let name = "session-" + UUID().uuidString
            guard mkdirat(fd, name, 0o700) == 0 else { throw Self.failure("createSession") }
            let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { let e = errno; _ = unlinkat(fd, name, AT_REMOVEDIR); throw Self.failure("openSession", e) }
            do { try Self.checkDir(child, privateDir: true) } catch { close(child); _ = unlinkat(fd, name, AT_REMOVEDIR); throw error }
            parentFD = fd; dirFD = child; session = name
            directory = base.appendingPathComponent(store, isDirectory: true).appendingPathComponent(name, isDirectory: true)
        } catch { close(fd); throw error }
    }
    func write(_ data: Data, name: String, createFile: ((Int32, String) -> Int32)? = nil) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", name == (name as NSString).lastPathComponent,
              !name.contains("/"), !name.contains("\\"), !name.contains("\0"), data.count <= 256 * 1024 * 1024 else {
            throw ClipError.invalid("导出文件名或大小无效")
        }
        let tmp = ".partial-" + UUID().uuidString
        let fd = createFile?(dirFD, tmp) ?? openat(dirFD, tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Self.failure("createFile") }
        var s = stat()
        guard fstat(fd, &s) == 0 else { let e = errno; close(fd); _ = unlinkat(dirFD, tmp, 0); throw Self.failure("statFile", e) }
        owned[tmp] = (s.st_dev, s.st_ino)
        defer { close(fd); removeOwned(tmp) }
        guard s.st_mode & S_IFMT == S_IFREG, s.st_uid == geteuid(), s.st_mode & 0o7777 == 0o600, s.st_nlink == 1 else { throw ClipError.invalid("导出暂存文件不安全。") }
        #if os(iOS)
        guard fcntl(fd, F_SETPROTECTIONCLASS, 3) == 0, fcntl(fd, F_GETPROTECTIONCLASS) == 3 else { throw Self.failure("protectFile") }
        #endif
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < data.count {
                let n = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), data.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Self.failure("writeFile", n == 0 ? EIO : errno) }
                offset += n
            }
        }
        guard fsync(fd) == 0 else { throw Self.failure("syncFile") }
        guard fstat(fd, &s) == 0 else { throw Self.failure("statFile") }
        guard s.st_mode & S_IFMT == S_IFREG, s.st_uid == geteuid(), s.st_mode & 0o7777 == 0o600, s.st_nlink == 1, s.st_size == Int64(data.count) else { throw ClipError.invalid("导出文件校验失败。") }
        // linkat is an atomic no-replace publication in the same directory.
        guard linkat(dirFD, tmp, dirFD, name, 0) == 0 else { throw Self.failure("publishFile") }
        owned[name] = (s.st_dev, s.st_ino)
        let url = directory.appendingPathComponent(name)
        urls.append(url)
        return url
    }
    private func removeOwned(_ name: String) {
        guard let identity = owned[name] else { return }
        var s = stat()
        if fstatat(dirFD, name, &s, AT_SYMLINK_NOFOLLOW) == 0 && s.st_dev == identity.0 && s.st_ino == identity.1 && s.st_mode & S_IFMT == S_IFREG {
            _ = unlinkat(dirFD, name, 0)
        }
        owned.removeValue(forKey: name)
    }
    func clear() {
        for name in Array(owned.keys) { removeOwned(name) }
        urls = []
        var a = stat(), b = stat()
        if fstat(dirFD, &a) == 0 && fstatat(parentFD, session, &b, AT_SYMLINK_NOFOLLOW) == 0 && a.st_dev == b.st_dev && a.st_ino == b.st_ino && b.st_mode & S_IFMT == S_IFDIR {
            _ = unlinkat(parentFD, session, AT_REMOVEDIR)
        }
    }
    deinit { clear(); close(dirFD); close(parentFD) }
}
