import Foundation
import Darwin

// Only fixed stage markers are accepted. Export uses this process's memory,
// never a URL or arbitrary on-disk contents (including a substituted symlink).
enum StartupLog {
    private static let lock = NSLock()
    private static var lines: [String] = []
    private static let stages: Set<String> = ["S0_MAIN", "S1_DID_FINISH_LAUNCHING", "S2_WINDOW_VISIBLE_REQUESTED", "S3_UIKIT_DID_APPEAR", "S4_SWIFTUI_REQUESTED", "S5_HOST_CREATED", "S6_ROOT_ON_APPEAR", "S6_MANAGER_ON_APPEAR_NO_SCAN", "S7_PRESENT_COMPLETED", "S8_SCAN_BUTTON", "S9_REFRESH_ENTERED", "S10_REPOSITORY_SCAN_ENTERED", "S11_SCAN_RETURNED", "S11_SCAN_THROWN"]
    static var exportText: String {
        lock.lock(); defer { lock.unlock() }
        if AppPaths.isContainerHome(AppPaths.root) {
            let url = AppPaths.root.appendingPathComponent("Library/WCM-stages.log")
            if AppPaths.isOwnedPath(url, root: AppPaths.root) {
                let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                if fd >= 0 {
                    defer { close(fd) }
                    var st = stat()
                    if fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_uid == getuid(), st.st_nlink == 1, st.st_size <= 66000 {
                        var bytes = [UInt8](repeating: 0, count: 66000)
                        let n = read(fd, &bytes, bytes.count)
                        if n > 0 {
                            let safe = String(decoding: bytes.prefix(n), as: UTF8.self).split(separator: "\n").filter {
                                $0.range(of: #"^\[WCM-(STARTUP|HELPER)\] (build=[0-9]+ S[0-9]+_[A-Z_]+|errno=[0-9]+ exit=-?[0-9]+)$"#, options: .regularExpression) != nil
                            }
                            return "自身容器固定阶段日志（不含个人数据）\n" + safe.joined(separator: "\n")
                        }
                    }
                }
            }
        }
        return "当前内存日志（容器日志暂不可用）\n" + lines.joined(separator: "\n")
    }
    static func record(_ stage: String) {
        guard stages.contains(stage) else { return }
        lock.lock(); defer { lock.unlock() }
        let line = "[WCM-STARTUP] build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown") \(stage)"
        append(line)
    }
    static func helper(error: Int32, status: Int32) {
        lock.lock(); defer { lock.unlock() }
        append("[WCM-HELPER] errno=\(error) exit=\(status)")
    }
    private static func append(_ line: String) {
        lines.append(line)
        if lines.count > 128 { lines.removeFirst() }
        guard AppPaths.isContainerHome(AppPaths.root) else { return }
        let root = open(AppPaths.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { return }; defer { close(root) }
        let library = openat(root, "Library", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard library >= 0 else { return }; defer { close(library) }
        let file = openat(library, "WCM-stages.log", O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard file >= 0 else { return }; defer { close(file) }
        var st = stat()
        guard fstat(file, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_uid == getuid(), st.st_nlink == 1 else { return }
        if st.st_size > 65536 { guard ftruncate(file, 0) == 0 else { return } }
        let data = Array((line + "\n").utf8)
        _ = data.withUnsafeBytes { write(file, $0.baseAddress, $0.count) }
        _ = fsync(file)
    }
}
