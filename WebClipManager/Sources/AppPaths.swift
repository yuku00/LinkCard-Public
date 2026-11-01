import Foundation
import Darwin

// Use the container and temporary directory supplied by the OS. Never rebind HOME.
enum AppPaths {
    static let identifier = "org.example.WebClipManager"
    static let root = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath()
    static var ready = false
    static private(set) var preparationStatus = "notChecked"
    static let documents = root.appendingPathComponent("Documents", isDirectory: true)
    static let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()

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

    // Validation only: no mkdir/chmod and no environment mutation during startup.
    @discardableResult static func prepare() -> Bool {
        let components = root.pathComponents
        let isContainer = components.count >= 5 && components.suffix(3).first == "Data"
            && components.suffix(2).first == "Application"
            && UUID(uuidString: root.lastPathComponent) != nil
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath()
        ready = isContainer && docs?.path == documents.path
            && isOwnedPath(documents, root: root) && isOwnedPath(temporary, root: root)
        preparationStatus = ready ? "OSContainerValidated" : "OSContainerValidationFailed; file import/export disabled"
        return ready
    }
}
