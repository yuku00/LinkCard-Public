import Foundation
import Darwin

// Backup-only: no code in this store invokes the private system deletion API.
enum RecycleStore {
    private static func checkedDir(_ fd: Int32, privateStore: Bool) throws {
        var s = stat()
        guard fstat(fd, &s) == 0, s.st_mode & S_IFMT == S_IFDIR else { throw ClipError.invalid("目录不可用") }
        if privateStore && (s.st_uid != geteuid() || (s.st_mode & 0o7777) != 0o700) {
            throw ClipError.invalid("回收目录的所有者或权限不安全")
        }
    }
    private static func openPath(_ path: String, createLast: Bool) throws -> Int32 {
        let canonical = BackgroundStore.normalizeSystemVar(URL(fileURLWithPath: path, isDirectory: true)).path
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ClipError.invalid("无法打开目录") }
        do {
            let components = canonical.split(separator: "/").map(String.init)
            for (index, part) in components.enumerated() {
                guard part != ".", part != ".." else { throw ClipError.invalid("路径无效") }
                var next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0 && errno == ENOENT && createLast && index == components.count - 1 {
                    guard mkdirat(fd, part, 0o700) == 0 || errno == EEXIST else { throw ClipError.invalid("无法创建目录") }
                    next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else { throw ClipError.invalid("目录不可访问或包含符号链接") }
                close(fd); fd = next
            }
            return fd
        } catch { close(fd); throw error }
    }
    private static func openStore() throws -> Int32 {
        let support = try openPath(NSHomeDirectory() + "/Library/Application Support", createLast: true)
        defer { close(support) }
        var store = openat(support, "WebClipRecycle", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if store < 0 && errno == ENOENT {
            guard mkdirat(support, "WebClipRecycle", 0o700) == 0 || errno == EEXIST else { throw ClipError.invalid("无法创建回收目录") }
            store = openat(support, "WebClipRecycle", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard store >= 0 else { throw ClipError.invalid("回收目录不可访问") }
        do { try checkedDir(store, privateStore: true); return store } catch { close(store); throw error }
    }
    struct Entry {
        let name: String
        let identifier: String?
    }
    static func entries() throws -> [Entry] {
        let store = try openStore(); defer { close(store) }
        let path = NSHomeDirectory() + "/Library/Application Support/WebClipRecycle"
        let names = try FileManager.default.contentsOfDirectory(atPath: path).filter { $0.hasPrefix(".incomplete-") }.sorted()
        return names.map { name in
            var buffer = [CChar](repeating: 0, count: 201)
            let result = WCMRecycleInspect(store, name, &buffer, UInt(buffer.count))
            return Entry(name: name, identifier: result == 0 ? String(cString: buffer) : nil)
        }
    }
    static func restore(_ name: String) throws {
        let store = try openStore(); defer { close(store) }
        let destination = try openPath("/private/var/mobile/Library/WebClips", createLast: false)
        defer { close(destination) }
        guard WCMRecycleRestore(store, destination, name, nil, nil) == 0 else {
            throw ClipError.invalid("恢复失败（错误码 \(errno)）；不覆盖已有目录，失败可能留下部分恢复目录")
        }
    }
    static func remove(_ name: String) throws {
        let store = try openStore(); defer { close(store) }
        guard WCMRecycleRemove(store, name) == 0 else { throw ClipError.invalid("清理失败（错误码 \(errno)）") }
    }
    static func backupTest(_ clip: Clip) throws {
        guard clip.title == "WCM-DELETE-TEST", !clip.removalDisallowed else {
            throw ClipError.invalid("只允许备份标题完全匹配且未禁止移除的测试书签")
        }
        let source = try openPath("/private/var/mobile/Library/WebClips", createLast: false)
        defer { close(source) }
        let support = try openPath(NSHomeDirectory() + "/Library/Application Support", createLast: true)
        defer { close(support) }
        var store = openat(support, "WebClipRecycle", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if store < 0 && errno == ENOENT {
            guard mkdirat(support, "WebClipRecycle", 0o700) == 0 || errno == EEXIST else { throw ClipError.invalid("无法创建回收目录") }
            store = openat(support, "WebClipRecycle", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard store >= 0 else { throw ClipError.invalid("回收目录不可访问") }
        defer { close(store) }
        try checkedDir(store, privateStore: true)
        guard WCMRecycleCopy(source, store, clip.id, UUID().uuidString, nil, nil) == 0 else {
            throw ClipError.invalid("备份未完成（错误码 \(errno)）；原目录未修改")
        }
    }
}
