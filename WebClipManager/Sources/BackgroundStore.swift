import Foundation
import Darwin

// Only this fixed namespace and its fixed image are touched; it is not Documents,
// WebClips, Notes, or a replacement for HOME. Same-UID processes are not isolated.
final class BackgroundStore {
    private let parent: URL
    private let verifyAncestors: Bool
    private let directory = "org.example.WebClipManager.background"
    private let imageName = "background.jpg"
    private let limit = 12 * 1024 * 1024

    // /var is an OS alias for /private/var on iOS. Rewrite only this
    // exact, trusted prefix; all other links are rejected by openat O_NOFOLLOW.
    static func normalizeSystemVar(_ url: URL) -> URL {
        let path = url.standardizedFileURL.path
        if path == "/var" || path.hasPrefix("/var/") {
            return URL(fileURLWithPath: "/private" + path, isDirectory: true)
        }
        return url.standardizedFileURL
    }
    init(parent: URL? = nil) {
        if let parent = parent {
            self.parent = Self.normalizeSystemVar(parent)
            self.verifyAncestors = false // XCTest supplies a private temporary parent.
        } else {
            self.parent = Self.normalizeSystemVar(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true))
            self.verifyAncestors = true
        }
    }

    private func failure(_ operation: String) -> Error { ReadAccess.failure(operation, errno) }
    private func checkedDirectory(_ fd: Int32, privateDirectory: Bool) throws {
        var s = stat()
        guard fstat(fd, &s) == 0 else { throw failure("statDirectory") }
        guard (s.st_mode & S_IFMT) == S_IFDIR,
              privateDirectory ? (s.st_uid == geteuid() && (s.st_mode & 0o7777) == 0o700)
                               : ((s.st_uid == geteuid() || s.st_uid == 0) && (s.st_mode & 0o022) == 0) else {
            throw ClipError.invalid("背景目录的所有者或权限不安全。")
        }
    }
    private func openParent(create: Bool) throws -> Int32? {
        guard parent.isFileURL, parent.path.hasPrefix("/"), !parent.pathComponents.contains("..") else {
            throw ClipError.invalid("背景路径无效。")
        }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failure("openDirectory") }
        do {
            if verifyAncestors { try checkedDirectory(fd, privateDirectory: false) }
            let components = Array(parent.pathComponents.dropFirst())
            for (index, component) in components.enumerated() {
                guard component != ".", component != "..", !component.contains("/") else { throw ClipError.invalid("背景路径无效。") }
                var next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0 && errno == ENOENT && index == components.count - 1 {
                    if !create { close(fd); return nil }
                    // Only create the missing Application Support directory, never chmod an existing shared parent.
                    if mkdirat(fd, component, 0o700) != 0 && errno != EEXIST { throw failure("createParent") }
                    next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else { throw failure("openDirectory") }
                close(fd); fd = next
                if verifyAncestors { try checkedDirectory(fd, privateDirectory: false) }
            }
            if !verifyAncestors { try checkedDirectory(fd, privateDirectory: true) }
            return fd
        } catch { close(fd); throw error }
    }
    private func openStore(create: Bool) throws -> Int32? {
        guard let p = try openParent(create: create) else { return nil }; defer { close(p) }
        var fd = openat(p, directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 && errno == ENOENT && create {
            if mkdirat(p, directory, 0o700) != 0 && errno != EEXIST { throw failure("createDirectory") }
            fd = openat(p, directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        if fd < 0 && errno == ENOENT && !create { return nil }
        guard fd >= 0 else { throw failure("openDirectory") }
        do { try checkedDirectory(fd, privateDirectory: true); return fd }
        catch { close(fd); throw error }
    }
    private func checkedFile(_ fd: Int32) throws -> Int {
        var s = stat()
        guard fstat(fd, &s) == 0 else { throw failure("statFile") }
        guard (s.st_mode & S_IFMT) == S_IFREG, s.st_uid == geteuid(),
              (s.st_mode & 0o7777) == 0o600, s.st_nlink == 1,
              s.st_size > 0, s.st_size <= Int64(limit) else { throw ClipError.invalid("已保存的背景文件不安全或大小无效。") }
        return Int(s.st_size)
    }
    func load() throws -> Data? {
        guard let dir = try openStore(create: false) else { return nil }; defer { close(dir) }
        let fd = openat(dir, imageName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 && errno == ENOENT { return nil }
        guard fd >= 0 else { throw failure("openFile") }; defer { close(fd) }
        let size = try checkedFile(fd)
        var data = Data(count: size)
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < size {
                let n = read(fd, buffer.baseAddress!.advanced(by: offset), size - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw ClipError.invalid("读取背景失败。") }
                offset += n
            }
        }
        return data
    }
    func save(_ data: Data, beforeCommit: (() throws -> Void)? = nil) throws {
        guard !data.isEmpty, data.count <= limit else { throw ClipError.invalid("背景图片大小无效。") }
        guard let dir = try openStore(create: true) else { throw ClipError.invalid("背景目录不可用。") }; defer { close(dir) }
        // Refuse an existing symlink, directory, hard link, or unsafe file rather than replacing it.
        let existing = openat(dir, imageName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if existing >= 0 { defer { close(existing) }; _ = try checkedFile(existing) }
        else if errno != ENOENT { throw failure("openFile") }
        let tmp = ".background-" + UUID().uuidString
        let fd = openat(dir, tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw failure("createFile") }
        var committed = false
        defer { close(fd); if !committed { _ = unlinkat(dir, tmp, 0) } }
        // Darwin protection class C = complete until first user authentication.
        // Set on the open descriptor, never via a path that can be swapped.
        guard fcntl(fd, F_SETPROTECTIONCLASS, 3) == 0,
              fcntl(fd, F_GETPROTECTIONCLASS) == 3 else { throw failure("protectFile") }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < data.count {
                let n = write(fd, buffer.baseAddress!.advanced(by: offset), data.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw failure("writeFile") }; offset += n
            }
        }
        guard fsync(fd) == 0 else { throw failure("syncFile") }
        _ = try checkedFile(fd)
        try beforeCommit?()
        guard renameat(dir, tmp, dir, imageName) == 0 else { throw failure("renameFile") }
        committed = true
        // The rename is atomic; directory fsync is best effort (not supported on every iOS filesystem).
        _ = fsync(dir)
    }
    func reset() throws {
        guard let dir = try openStore(create: false) else { return }; defer { close(dir) }
        let fd = openat(dir, imageName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 && errno == ENOENT { return }
        guard fd >= 0 else { throw failure("openFile") }; defer { close(fd) }
        _ = try checkedFile(fd)
        guard unlinkat(dir, imageName, 0) == 0 else { throw failure("unlinkFile") }
        _ = fsync(dir)
    }
}
