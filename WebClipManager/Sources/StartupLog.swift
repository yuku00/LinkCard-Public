import Foundation

// Diagnostic build only. Never pass URLs, titles, counts or error descriptions here.
enum StartupLog {
    private static let lock = NSLock()
    static func logURL(documents: URL) -> URL? {
        // Fail closed if installation unexpectedly gives us /var/mobile/Documents.
        let base = documents.resolvingSymlinksInPath().standardizedFileURL
        let parts = base.pathComponents
        guard parts.count >= 6,
              parts.suffix(5).first == "Containers",
              parts[parts.count - 4] == "Data",
              parts[parts.count - 3] == "Application",
              UUID(uuidString: parts[parts.count - 2]) != nil,
              parts.last == "Documents" else { return nil }
        let target = base.appendingPathComponent("WebClipManager", isDirectory: true)
            .appendingPathComponent("startup-build5.log")
        guard target.resolvingSymlinksInPath().standardizedFileURL.path == target.path else { return nil }
        return target
    }
    static var url: URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return logURL(documents: documents)
    }
    static func record(_ stage: String) {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        guard let target = url else { return }
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
