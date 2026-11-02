import Foundation

// Confirmation is collected by UIKit. This coordinator never retries a deletion.
enum ExperimentalDelete {
    static func run(_ clip: Clip, firstConfirmed: Bool, secondConfirmed: Bool,
                    backup: (Clip) throws -> Void = RecycleStore.backupTest,
                    bridge: (String) -> [AnyHashable: Any] = { WCMExperimentalDelete($0) }) throws -> String {
        guard firstConfirmed && secondConfirmed else { return "已取消；未备份或删除。" }
        guard clip.title == "WCM-DELETE-TEST", !clip.removalDisallowed else {
            throw ClipError.invalid("只允许未禁止移除的 WCM-DELETE-TEST 单项")
        }
        try backup(clip) // Includes verification of this transaction's manifest and identifier.
        let result = bridge(clip.id) // Bridge rechecks original title, policy, ID and path.
        guard result["called"] as? Bool == true else {
            return "已备份但拒绝删除：\(result["reason"] as? String ?? "未知错误")。副本保护有限。"
        }
        let returned = (result["returned"] as? Bool).map { $0 ? "true" : "false" } ?? "未知"
        return "已调用一次 removeFromDisk，返回 \(returned)；源目录\(result["source"] as? String ?? "未知")。未确认桌面清理；恢复不保证图标/元数据，回收副本保护有限。"
    }
}
