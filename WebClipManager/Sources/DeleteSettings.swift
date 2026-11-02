import Foundation

// A missing, unreadable, or malformed setting always disables deletion.
struct DeleteSettings {
    private let store: BackgroundStore
    private static let enabledValue = Data("delete-enabled-v1\n".utf8)
    private static let disabledValue = Data("delete-disabled-v1\n".utf8)

    init(parent: URL? = nil) {
        store = BackgroundStore(parent: parent, purpose: .deletionSettings)
    }

    var isEnabled: Bool {
        guard let data = try? store.load() else { return false }
        return data == Self.enabledValue
    }

    func setEnabled(_ enabled: Bool) throws {
        try store.save(enabled ? Self.enabledValue : Self.disabledValue)
    }
}

// Missing, unreadable and unrecognized values never enable reading Notes.
struct NotesAutoReadSettings {
    private let store: BackgroundStore
    private static let enabledValue = Data("notes-auto-read-enabled-v1\n".utf8)
    private static let disabledValue = Data("notes-auto-read-disabled-v1\n".utf8)

    init(parent: URL? = nil) {
        store = BackgroundStore(parent: parent, purpose: .notesAutoReadSettings)
    }
    var isEnabled: Bool {
        guard let data = try? store.load() else { return false }
        return data == Self.enabledValue
    }
    func setEnabled(_ enabled: Bool) throws {
        try store.save(enabled ? Self.enabledValue : Self.disabledValue)
    }
}


// Shared selection operations, independent of presentation or data source.
enum SelectionPolicy {
    static func selectVisible(_ visible: Set<String>, selected: inout Set<String>) { selected.formUnion(visible) }
    static func clear(_ selected: inout Set<String>) { selected.removeAll() }
    static func toggle(_ id: String, selected: inout Set<String>) {
        if !selected.insert(id).inserted { selected.remove(id) }
    }
    static func afterRead(success: Bool, selected: inout Set<String>) {
        if success { selected.removeAll() }
    }
}

struct NotesAutoReadPolicy {
    private(set) var attempted = false
    mutating func beginIfAllowed(enabled: Bool, busy: Bool, hasSelection: Bool, readState: String) -> Bool {
        guard enabled, !attempted, !busy, !hasSelection, readState == "notRead" else { return false }
        attempted = true
        return true
    }
}
