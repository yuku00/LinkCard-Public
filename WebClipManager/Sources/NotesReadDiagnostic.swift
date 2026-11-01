import Foundation

struct NotesReadDiagnostic: Codable {
    let state: String
    let failure: AccessError?
    private static let lock = NSLock()
    private static var latest = NotesReadDiagnostic(state: "notRead", failure: nil)
    static func record(state: String, error: Error? = nil) {
        lock.lock(); defer { lock.unlock() }
        let allowed = ["notRead", "reading", "readable", "failed"]
        latest = Self(state: allowed.contains(state) ? state : "notRead", failure: error.map(AccessError.capture))
    }
    static func capture() -> Self {
        lock.lock(); defer { lock.unlock() }
        return latest
    }
}
