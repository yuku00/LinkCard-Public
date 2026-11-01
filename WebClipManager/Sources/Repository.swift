import Foundation
import Darwin

struct Clip: Identifiable, Sendable, Codable {
    let id: String
    let title: String
    let url: String
    let fullScreen: Bool
    let removalDisallowed: Bool
    let icon: Data?
}

struct ItemResult: Identifiable, Sendable {
    let id: String
    let message: String
}

struct Scan: Sendable {
    var clips: [Clip] = []
    var issues: [ItemResult] = []
    var firstFailure: AccessError?
}

struct Backup: Sendable {
    let data: Data
    let results: [ItemResult]
}

enum ClipError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let reason): return reason }
    }
}

actor Repository {
    static let deviceRoot = URL(fileURLWithPath: "/var/mobile/Library/WebClips", isDirectory: true)
    private let root: URL
    private let fm = FileManager.default
    private let fileLimit = 64 * 1024 * 1024
    private let backupLimit = 256 * 1024 * 1024

    init(root: URL = Repository.deviceRoot) { self.root = root }

    private func check(_ url: URL, directory: Bool) throws {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw ReadAccess.failure("lstat", errno) }
        let kind = value.st_mode & S_IFMT
        guard kind == (directory ? S_IFDIR : S_IFREG) else {
            throw ReadAccess.failure("fileType", kind == S_IFLNK ? ELOOP : (directory ? ENOTDIR : EINVAL))
        }
    }

    private func folder(_ id: String) throws -> URL {
        guard !id.isEmpty, id == (id as NSString).lastPathComponent,
              !id.contains("\\"), id.hasSuffix(".webclip") else {
            throw ClipError.invalid("无效 WebClip 目录标识")
        }
        try check(root, directory: true)
        let result = root.appendingPathComponent(id, isDirectory: true)
        try check(result, directory: true)
        return result
    }

    private func read(_ url: URL, limit: Int) throws -> Data {
        try check(url, directory: false)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw ReadAccess.failure("openFile", errno) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var value = stat()
        guard fstat(fd, &value) == 0 else { throw ReadAccess.failure("fstat", errno) }
        guard value.st_mode & S_IFMT == S_IFREG else { throw ReadAccess.failure("fileType", EINVAL) }
        guard value.st_size <= limit else { throw ClipError.invalid("文件超过读取上限") }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(1024 * 1024, limit + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= limit else { throw ClipError.invalid("读取时文件超过上限") }
        }
        return data
    }

    func accessDiagnostics() -> AccessSnapshot { ReadAccess.diagnostics() }

    func scan() throws -> Scan {
        StartupLog.record("S10_REPOSITORY_SCAN_ENTERED")
        if root == Self.deviceRoot { return try HelperReader.scan() }
        try check(root, directory: true)
        let entries = try ReadAccess.entries(root)
        var result = Scan()
        for entry in entries.filter({ $0.pathExtension == "webclip" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let id = entry.lastPathComponent
            do {
                let dir = try folder(id)
                let data = try read(dir.appendingPathComponent("Info.plist"), limit: 2 * 1024 * 1024)
                guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                    throw ClipError.invalid("Info.plist 不是字典")
                }
                var icon: Data?
                for name in ["icon.png", "icon@2x.png", "icon@3x.png"] {
                    let path = dir.appendingPathComponent(name)
                    if fm.fileExists(atPath: path.path) {
                        do { icon = try read(path, limit: 8 * 1024 * 1024) }
                        catch {
                            if result.firstFailure == nil { result.firstFailure = AccessError.capture(error) }
                            result.issues.append(ItemResult(id: id + "/" + name, message: AccessError.capture(error).summary))
                        }
                        break
                    }
                }
                result.clips.append(Clip(id: id, title: plist["Title"] as? String ?? id,
                                         url: plist["URL"] as? String ?? "",
                                         fullScreen: plist["FullScreen"] as? Bool ?? false,
                                         removalDisallowed: plist["RemovalDisallowed"] as? Bool ?? false,
                                         icon: icon))
            } catch {
                if result.firstFailure == nil { result.firstFailure = AccessError.capture(error) }
                result.issues.append(ItemResult(id: id, message: AccessError.capture(error).summary))
            }
        }
        return result
    }

    // Exact URL strings only: do not conflate fragments, query order or trailing slashes.
    nonisolated static func duplicateIDs(_ clips: [Clip]) -> Set<String> {
        let groups = Dictionary(grouping: clips.filter { !$0.url.isEmpty }, by: \.url)
        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    }

    func backup(ids: [String]) throws -> Backup {
        guard root != Self.deviceRoot else { throw ClipError.invalid("此候选仅接通只读书签扫描；设备目录完整备份尚未接入辅助进程。") }
        var entries: [[String: Any]] = []
        var results: [ItemResult] = []
        var used = 0
        for id in ids.sorted() {
            do {
                let directory = try folder(id)
                var files: [String: Data] = [:]
                var directories: [String] = []
                var itemSize = 0
                func walk(_ parent: URL, prefix: String) throws {
                    for child in try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                        let relative = prefix + child.lastPathComponent
                        let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        guard values.isSymbolicLink != true else { throw ClipError.invalid("备份拒绝符号链接") }
                        if values.isDirectory == true {
                            directories.append(relative)
                            try walk(child, prefix: relative + "/")
                        } else {
                            let bytes = try read(child, limit: fileLimit)
                            itemSize += bytes.count
                            guard used + itemSize <= backupLimit else { throw ClipError.invalid("备份总量超过 256 MiB 上限") }
                            files[relative] = bytes
                        }
                    }
                }
                try walk(directory, prefix: "")
                guard files["Info.plist"] != nil else { throw ClipError.invalid("备份缺失 Info.plist") }
                used += itemSize
                entries.append(["directory": id, "directories": directories, "files": files])
                results.append(ItemResult(id: id, message: "已读取完整目录；需完成系统导出才保存到目标位置"))
            } catch { results.append(ItemResult(id: id, message: "备份失败：" + error.localizedDescription)) }
        }
        guard !entries.isEmpty else { throw ClipError.invalid(results.map { "\($0.id)：\($0.message)" }.joined(separator: "\n")) }
        let manifest: [String: Any] = ["format": "WebClipManagerBackup", "version": 1,
            "createdAt": Date(), "entries": entries,
            "results": results.map { ["id": $0.id, "message": $0.message] }]
        return Backup(data: try PropertyListSerialization.data(fromPropertyList: manifest, format: .binary, options: 0), results: results)
    }

    // No private call, filesystem removal, Safari cleanup or success claim.
    func delete(ids: [String]) -> [ItemResult] {
        ids.sorted().map { ItemResult(id: $0, message: "未删除：尚无经 iOS 16.6 真机验证、等同主屏幕删除的受支持调用路径。请在主屏幕手动删除。") }
    }
}
