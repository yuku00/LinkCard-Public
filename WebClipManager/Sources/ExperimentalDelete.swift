import Foundation

// Confirmation is collected by UIKit. This coordinator never retries a deletion.
enum ExperimentalDelete {
    static func succeeded(_ result: [AnyHashable: Any]) -> Bool {
        result["called"] as? Bool == true && result["returned"] as? Bool == true && result["source"] as? String == "不存在"
    }
    static func run(_ clip: Clip, firstConfirmed: Bool, secondConfirmed: Bool,
                    progress: (String) -> Void = { _ in },
                    backup: (Clip) throws -> Void = RecycleStore.backupTest,
                    enabled: () -> Bool = { DeleteSettings().isEnabled },
                    bridge: (String) -> [AnyHashable: Any] = { WCMExperimentalDelete($0) }) throws -> String {
        guard firstConfirmed && secondConfirmed else { return "已取消；未备份或删除。" }
        guard enabled() else { throw ClipError.invalid("删除开关已关闭") }
        guard !clip.removalDisallowed else {
            throw ClipError.invalid("此书签禁止移除")
        }
        try backup(clip) // Includes verification of this transaction's manifest and identifier.
        guard enabled() else { throw ClipError.invalid("删除开关已关闭；已创建回收副本，未删除") }
        progress("备份已验证，正在核验策略并尝试系统删除…")
        let result = bridge(clip.id) // Bridge rechecks policy, ID and path.
        guard result["called"] as? Bool == true else {
            return "已备份但拒绝删除：\(result["reason"] as? String ?? "未知错误")。副本保护有限。"
        }
        let returned = (result["returned"] as? Bool).map { $0 ? "true" : "false" } ?? "未知"
        return "已调用一次 removeFromDisk，返回 \(returned)；源目录\(result["source"] as? String ?? "未知")。未确认桌面清理；恢复不保证图标/元数据，回收副本保护有限。"
    }
}
