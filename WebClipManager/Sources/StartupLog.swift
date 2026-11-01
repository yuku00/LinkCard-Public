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
        return "仅当前进程内存日志；重启后不保留，不包含上次崩溃日志。\n" + lines.joined(separator: "\n")
    }
    static func record(_ stage: String) {
        guard stages.contains(stage) else { return }
        lock.lock(); defer { lock.unlock() }
        let line = "[WCM-STARTUP] build=10 \(stage)"
        lines.append(line)
        if lines.count > 128 { lines.removeFirst() }
    }
}
