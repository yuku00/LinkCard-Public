import Foundation

// Diagnostic build only. Never pass URLs, titles, counts or error descriptions here.
enum StartupLog {
    private static let lock = NSLock()
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("startup-build3.log")
    }
    static func record(_ stage: String) {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        let target = url
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if !fm.fileExists(atPath: target.path) || bytes > 65536 {
                try Data().write(to: target, options: .atomic)
            }
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            let line = "[WCM-STARTUP] \(Date().timeIntervalSince1970) build=\(build) \(stage)\n"
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.synchronize()
        } catch {
            // A failed log write must not terminate the app; no sensitive error output.
        }
    }
}
