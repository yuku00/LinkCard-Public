import Foundation
import Darwin

// Only files created by this instance are removed. Never clean a shared directory.
final class ExportStaging {
    let directory: URL
    private(set) var urls: [URL] = []
    init() throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        var template = Array(parent.appendingPathComponent("WebClipManager-export-XXXXXX").path.utf8CString)
        guard let path = mkdtemp(&template) else { throw ReadAccess.failure("openDirectory", errno) }
        directory = URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }
    func write(_ data: Data, name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", name == (name as NSString).lastPathComponent,
              !name.contains("\\"), !name.contains("\0"), data.count <= 256 * 1024 * 1024 else {
            throw ClipError.invalid("导出文件名或大小无效")
        }
        let url = directory.appendingPathComponent(name)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ReadAccess.failure("openFile", errno) }
        urls.append(url)
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        return url
    }
    func clear() {
        for url in urls { _ = unlink(url.path) }
        urls = []
        _ = rmdir(directory.path)
    }
    deinit { clear() }
}
