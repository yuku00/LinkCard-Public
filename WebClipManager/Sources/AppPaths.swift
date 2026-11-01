import Foundation
import Darwin

// Non-container launch receives HOME=/var/mobile and TMPDIR=/var/tmp.
// Never derive application writes from those shared directories.
enum AppPaths {
    static let identifier = "org.example.WebClipManager"
    #if targetEnvironment(simulator)
    // Simulator already supplies an app-exclusive container; do not move XCTest's home.
    static let root = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath()
    #else
    static let root = URL(fileURLWithPath: "/private/var/mobile/Library/Application Support/" + identifier)
    #endif
    static var ready = false
    static let documents = root.appendingPathComponent("Documents", isDirectory: true)
    static let temporary = root.appendingPathComponent("tmp", isDirectory: true)

    static func isOwnedPath(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        guard path.hasPrefix(base + "/"), url.resolvingSymlinksInPath().standardizedFileURL.path == path else { return false }
        // Foundation may leave a symlink unresolved when the final leaf does not
        // exist. Inspect every existing ancestor, not only the prospective leaf.
        var current = ""
        for part in URL(fileURLWithPath: path).pathComponents.dropFirst() {
            current += "/" + part
            var st = stat()
            if lstat(current, &st) == 0 {
                if (st.st_mode & S_IFMT) == S_IFLNK { return false }
            } else if errno != ENOENT { return false }
        }
        return true
    }

    // Walk without following symlinks; create only the app root and descendants.
    private static func directory(_ url: URL) throws {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(.EACCES) }
        defer { close(fd) }
        var path = ""
        for part in url.pathComponents.dropFirst() {
            path += "/" + part
            let owned = path == root.path || path.hasPrefix(root.path + "/")
            if owned && mkdirat(fd, part, 0o700) != 0 && errno != EEXIST { throw POSIXError(.EACCES) }
            let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw POSIXError(.EACCES) }
            close(fd); fd = next
            if owned {
                var st = stat()
                guard fstat(fd, &st) == 0, st.st_uid == geteuid(), fchmod(fd, 0o700) == 0 else { throw POSIXError(.EACCES) }
            }
        }
    }

    @discardableResult static func prepare() -> Bool {
        do {
            for url in [root, documents, temporary, root.appendingPathComponent("Library/Preferences"), root.appendingPathComponent("Library/Caches")] { try directory(url) }
            guard setenv("HOME", root.path, 1) == 0,
                  setenv("CFFIXED_USER_HOME", root.path, 1) == 0,
                  setenv("TMPDIR", temporary.path + "/", 1) == 0 else { return false }
            // Foundation may have cached its paths. Fail closed rather than staging
            // fileExporter documents or logs into a shared home/temp directory.
            let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath()
            let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath()
            ready = home.path == root.path && temp.path == temporary.path && docs?.path == documents.path
        } catch { ready = false }
        return ready
    }
}
