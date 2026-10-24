// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CryptoKit
import Combine

struct LocalCard: Codable, Identifiable {
    let id: UUID
    var name: String
    let fileExtension: String
    let size: Int
    let format: String
    let imported: Date
    let sha256: String
}

enum CardLibraryError: LocalizedError {
    case invalidName, invalidFile, tooLarge, storage
    var errorDescription: String? {
        switch self {
        case .invalidName: return "名称不能为空，不能包含路径、控制字符或 ..，最多 80 个字符。"
        case .invalidFile: return "请选择自己的 bin、dump 或 txt 普通文件；不支持空文件或符号链接。"
        case .tooLarge: return "文件超过 2 MiB 上限，未导入。"
        case .storage: return "本地文件操作失败。请检查可用空间，或解锁后重试。"
        }
    }
}

final class LocalCardLibrary: ObservableObject {
    @Published private(set) var cards = [LocalCard]()
    @Published var message: String?
    private let fm = FileManager.default
    private let limit = 2 * 1024 * 1024
    private var root: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalCards", isDirectory: true)
    }
    init() {
        // Remove protected share copies left by an interrupted previous launch.
        if let urls = try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil) {
            for url in urls where url.lastPathComponent.hasPrefix("CardExport-") {
                try? fm.removeItem(at: url)
            }
        }
        reload()
    }
    static func cleanName(_ raw: String) throws -> String {
        let value = raw.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 80, !value.contains(".."),
              value.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:").union(.controlCharacters)) == nil else { throw CardLibraryError.invalidName }
        return value
    }
    private func prepare() throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true,
                               attributes: [.protectionKey: FileProtectionType.complete])
        var url = root; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
    func reload() {
        do {
            try prepare()
            let urls = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])
            var loaded = [LocalCard](); var skipped = false
            for url in urls {
                do {
                    guard let id = UUID(uuidString: url.lastPathComponent),
                          try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw CardLibraryError.storage }
                    let data = try Data(contentsOf: url.appendingPathComponent("metadata.json"))
                    let card = try JSONDecoder().decode(LocalCard.self, from: data)
                    guard card.id == id, ["bin", "dump", "txt"].contains(card.fileExtension),
                          (1...limit).contains(card.size), card.sha256.count == 64 else { throw CardLibraryError.storage }
                    _ = try Self.cleanName(card.name)
                    loaded.append(card)
                } catch { skipped = true }
            }
            cards = loaded.sorted { $0.imported > $1.imported }
            if skipped { message = "部分本地记录损坏，未展示；没有修改原文件。" }
        } catch { message = CardLibraryError.storage.localizedDescription }
    }
    func importFile(_ url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
            do { try importCoordinated(source) } catch { failure = error }
        }
        if let error = failure as? CardLibraryError { message = error.localizedDescription }
        else if failure != nil || coordinationError != nil { message = CardLibraryError.storage.localizedDescription }
        reload()
    }
    private func importCoordinated(_ source: URL) throws {
        let ext = source.pathExtension.lowercased()
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard ["bin", "dump", "txt"].contains(ext), values.isRegularFile == true,
              values.isSymbolicLink != true else { throw CardLibraryError.invalidFile }
        guard (values.fileSize ?? 0) <= limit else { throw CardLibraryError.tooLarge }
        // Validate source filename before using even its basename as a display label.
        _ = try Self.cleanName(source.lastPathComponent)
        let name = try Self.cleanName(source.deletingPathExtension().lastPathComponent)
        let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard !data.isEmpty else { throw CardLibraryError.invalidFile }
        guard data.count <= limit else { throw CardLibraryError.tooLarge }
        let card = LocalCard(id: UUID(), name: name, fileExtension: ext, size: data.count,
                             format: Self.describe(data, ext: ext), imported: Date(),
                             sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        try prepare(); let dir = folder(card.id)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.protectionKey: FileProtectionType.complete])
            try write(data, to: dir.appendingPathComponent("payload"))
            try write(JSONEncoder().encode(card), to: dir.appendingPathComponent("metadata.json"))
        } catch { try? fm.removeItem(at: dir); throw CardLibraryError.storage }
    }
    static func describe(_ data: Data, ext: String) -> String {
        if ext == "txt", let text = String(data: data, encoding: .utf8) {
            let compact = text.filter { !$0.isWhitespace }
            if !compact.isEmpty, compact.count.isMultiple(of: 2), compact.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) {
                return "十六进制文本候选 · \(compact.count / 2) 字节 · 完整性未验证"
            }
            return "UTF-8 文本 · 未识别卡格式"
        }
        if ext != "txt", [320, 540, 572, 1024, 2048, 4096].contains(data.count) {
            return "二进制转储候选 · 仅长度线索 · 卡型与完整性未验证"
        }
        return "未知格式 · 原样保存，不补齐缺失数据"
    }
    func rename(_ card: LocalCard, to name: String) {
        do {
            var updated = card; updated.name = try Self.cleanName(name)
            try write(JSONEncoder().encode(updated), to: folder(card.id).appendingPathComponent("metadata.json")); reload()
        } catch let error as CardLibraryError { message = error.localizedDescription }
        catch { message = CardLibraryError.storage.localizedDescription }
    }
    func delete(_ card: LocalCard) {
        do { try fm.removeItem(at: folder(card.id)); reload() }
        catch { message = CardLibraryError.storage.localizedDescription }
    }
    func export(_ card: LocalCard) throws -> URL {
        let payload = folder(card.id).appendingPathComponent("payload")
        let data = try Data(contentsOf: payload)
        guard data.count == card.size,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == card.sha256 else { throw CardLibraryError.storage }
        let directory = fm.temporaryDirectory.appendingPathComponent("CardExport-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.protectionKey: FileProtectionType.complete])
        let url = directory.appendingPathComponent(try Self.cleanName(card.name)).appendingPathExtension(card.fileExtension)
        do { try write(data, to: url); return url }
        catch { try? fm.removeItem(at: directory); throw error }
    }
    static func removeExport(_ url: URL?) {
        guard let url = url, url.deletingLastPathComponent().lastPathComponent.hasPrefix("CardExport-") else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
