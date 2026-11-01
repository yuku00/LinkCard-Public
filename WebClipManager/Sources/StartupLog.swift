import Foundation
import Darwin

// Only fixed stage markers are accepted. Export uses this process's memory,
// never a URL or arbitrary on-disk contents (including a substituted symlink).
enum StartupLog {
    private static let lock = NSLock()
    private static var lines: [String] = []
    private static let stages: Set<String> = ["S0_MAIN", "S1_DID_FINISH_LAUNCHING", "S2_WINDOW_VISIBLE_REQUESTED", "S3_UIKIT_DID_APPEAR", "S4_SWIFTUI_REQUESTED", "S5_HOST_CREATED", "S6_ROOT_ON_APPEAR", "S6_MANAGER_ON_APPEAR_NO_SCAN", "S7_PRESENT_COMPLETED", "S8_SCAN_BUTTON", "S9_REFRESH_ENTERED", "S10_REPOSITORY_SCAN_ENTERED", "S11_SCAN_RETURNED", "S11_SCAN_THROWN"]
    static func logURL(documents: URL) -> URL? {
        guard documents.standardizedFileURL.path == AppPaths.documents.path,
              AppPaths.isOwnedPath(documents, root: AppPaths.root) else { return nil }
        let target = documents.appendingPathComponent("startup-build7.log")
        return AppPaths.isOwnedPath(target, root: AppPaths.root) ? target : nil
    }
    static var url: URL? { AppPaths.ready ? logURL(documents: AppPaths.documents) : nil }
    static var exportText: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
    static func record(_ stage: String) {
        guard stages.contains(stage) else { return }
        lock.lock(); defer { lock.unlock() }
        let line = "[WCM-STARTUP] build=7 \(stage)"
        lines.append(line)
        if lines.count > 128 { lines.removeFirst() }
        guard let target = url else { return }
        let fd = open(target.path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_uid == geteuid(), (st.st_mode & S_IFMT) == S_IFREG, st.st_nlink == 1 else { return }
        if st.st_size > 65536 { guard ftruncate(fd, 0) == 0 else { return } }
        let data = Data((line + "\n").utf8)
        data.withUnsafeBytes { buffer in
            if let base = buffer.baseAddress { _ = Darwin.write(fd, base, buffer.count) }
        }
    }
}
