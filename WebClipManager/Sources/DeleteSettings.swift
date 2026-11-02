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
