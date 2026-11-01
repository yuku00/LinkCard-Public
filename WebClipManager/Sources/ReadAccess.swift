import Foundation
import Darwin

// Never serialize NSError.userInfo/descriptions: they can contain bookmark names/URLs.
struct AccessError: Codable, Sendable {
    let domain: String
    let code: Int
    let underlyingPOSIX: Int?
    let operation: String
    let category: String

    static func capture(_ error: Error) -> AccessError {
        let top = error as NSError
        var current = top
        var posix: Int?
        for _ in 0..<8 {
            if current.domain == NSPOSIXErrorDomain { posix = current.code; break }
            guard let next = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = next
        }
        let operations = ["lstat", "openDirectory", "fdopendir", "readdir", "openFile", "fstat", "fileType"]
        let rawOperation = top.userInfo["operation"] as? String ?? ""
        let category: String
        switch posix {
        case Int(ENOENT): category = "notFound"
        case Int(ENOTDIR): category = "notDirectory"
        case Int(ELOOP): category = "symlinkRejected"
        case Int(EACCES): category = "accessDeniedCauseUndetermined"
        case Int(EPERM): category = "operationNotPermittedCauseUndetermined"
        default: category = "otherFailure"
        }
        return AccessError(domain: [NSPOSIXErrorDomain, NSCocoaErrorDomain].contains(top.domain) ? top.domain : "other",
            code: top.code, underlyingPOSIX: posix,
            operation: operations.contains(rawOperation) ? rawOperation : "scan", category: category)
    }
    var summary: String {
        "\(operation): \(domain)/\(code), POSIX=\(underlyingPOSIX.map(String.init) ?? "none"), \(category)"
    }
}

struct PathAccess: Codable, Sendable {
    let path: String
    let resolvedPath: String?
    let realpathErrno: Int32
    let isSymbolicLink: Bool?
    let lstatErrno: Int32
    let openSucceeded: Bool
    let openErrno: Int32
    let fstatErrno: Int32?
    let ownerUID: UInt32?
    let ownerGID: UInt32?
    let mode: UInt16?
}

struct AccessSnapshot: Codable, Sendable {
    let uid: UInt32
    let euid: UInt32
    let gid: UInt32
    let egid: UInt32
    let paths: [PathAccess]
}

enum ReadAccess {
    // Fixed system paths only, including the real parent of /var. Never enumerate user data here.
    static let diagnosticPaths = ["/", "/var", "/var/mobile", "/var/mobile/Library", "/var/mobile/Library/WebClips",
        "/private", "/private/var", "/private/var/mobile", "/private/var/mobile/Library", "/private/var/mobile/Library/WebClips",
        "/private/var/mobile/Containers/Shared/AppGroup"]

    static func failure(_ operation: String, _ code: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: ["operation": operation])
    }
    static func openDirectory(_ path: String) throws -> Int32 {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failure("openDirectory", errno) }
        return fd
    }
    static func entries(_ url: URL) throws -> [URL] {
        let fd = try openDirectory(url.path)
        guard let directory = fdopendir(fd) else {
            let code = errno
            close(fd)
            throw failure("fdopendir", code)
        }
        defer { closedir(directory) }
        var entries: [URL] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 { throw failure("readdir", errno) }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { entries.append(url.appendingPathComponent(name)) }
        }
        return entries
    }
    static func diagnostics() -> AccessSnapshot {
        let paths = diagnosticPaths.map { path -> PathAccess in
            var metadata = stat()
            let statOK = lstat(path, &metadata) == 0
            let statCode: Int32 = statOK ? 0 : errno
            let link = statOK ? (metadata.st_mode & S_IFMT) == S_IFLNK : nil
            let resolved = realpath(path, nil)
            let realCode: Int32 = resolved == nil ? errno : 0
            let raw = resolved.map { String(cString: $0) }
            if let resolved { free(resolved) }
            // Follow known system aliases in this probe only; production root/entries reject final symlinks.
            let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            let openCode: Int32 = fd < 0 ? errno : 0
            var info = stat()
            let infoOK = fd >= 0 && fstat(fd, &info) == 0
            let infoCode: Int32? = fd < 0 ? nil : (infoOK ? 0 : errno)
            if fd >= 0 { close(fd) }
            return PathAccess(path: path, resolvedPath: raw.map { diagnosticPaths.contains($0) ? $0 : "redacted" },
                realpathErrno: realCode, isSymbolicLink: link, lstatErrno: statCode,
                openSucceeded: fd >= 0, openErrno: openCode, fstatErrno: infoCode,
                ownerUID: infoOK ? info.st_uid : nil, ownerGID: infoOK ? info.st_gid : nil,
                mode: infoOK ? UInt16(info.st_mode & 0o7777) : nil)
        }
        return AccessSnapshot(uid: getuid(), euid: geteuid(), gid: getgid(), egid: getegid(), paths: paths)
    }
}
