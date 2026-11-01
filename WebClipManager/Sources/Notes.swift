import Foundation
import SwiftUI

struct ImportedNote: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let text: String
}

enum NoteFiles {
    static let fileLimit = 2 * 1024 * 1024
    static let totalLimit = 16 * 1024 * 1024
    static func decode(_ data: Data) throws -> String {
        guard data.count <= fileLimit else { throw ClipError.invalid("单篇最多 2 MiB") }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            throw ClipError.invalid("仅支持 UTF-8 TXT / Markdown 文本")
        }
        return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
    static func filename(_ title: String, index: Int, markdown: Bool) -> String {
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
        let clean = title.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(format: "%03d-", index + 1) + String((clean.isEmpty ? "备忘录" : clean).prefix(60)) + (markdown ? ".md" : ".txt")
    }
    static func read(_ url: URL) throws -> ImportedNote {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard ["txt", "md"].contains(url.pathExtension.lowercased()) else { throw ClipError.invalid("请选择 txt 或 md 文件") }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= fileLimit else { throw ClipError.invalid("不是普通文件或超过 2 MiB") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(64 * 1024, fileLimit + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= fileLimit else { throw ClipError.invalid("读取时文件超过 2 MiB") }
        }
        return ImportedNote(title: url.deletingPathExtension().lastPathComponent, text: try decode(data))
    }
}

@MainActor
final class NotesModel: ObservableObject {
    @Published var notes: [ImportedNote] = []
    @Published var selected: Set<UUID> = []
    @Published var busy = false
    @Published var status = "主动读取 Apple Notes 的未锁定正文；数据只在内存停留，确认后才导出。"
    @Published var failures: [String] = []
    func loadAppleNotes() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        NotesReadDiagnostic.record(state: "reading")
        do {
            let batch = try await Task.detached { try AppleNotesStore.load() }.value
            notes = batch.notes; selected = Set(notes.map(\.id)); failures = []
            status = batch.summary
            NotesReadDiagnostic.record(state: "readable")
        } catch {
            NotesReadDiagnostic.record(state: "failed", error: error)
            status = "读取未完成；原批次保留。\(error.localizedDescription)"
        }
    }
    func clear() {
        notes = []; selected = []; failures = []
        status = "已清除当前内存中的笔记，不修改 Apple Notes。"
    }
    func load(_ urls: [URL]) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let result = await Task.detached { () -> ([ImportedNote], [String]) in
            var notes: [ImportedNote] = []; var errors: [String] = []; var bytes = 0
            for (index, url) in urls.prefix(100).enumerated() {
                do {
                    let note = try NoteFiles.read(url)
                    guard bytes + note.text.utf8.count <= NoteFiles.totalLimit else { throw ClipError.invalid("本批总量超过 16 MiB") }
                    bytes += note.text.utf8.count; notes.append(note)
                } catch { errors.append("文件 \(index + 1)：\(error.localizedDescription)") }
            }
            if urls.count > 100 { errors.append("每批最多 100 个文件，其余未导入") }
            return (notes, errors)
        }.value
        notes = result.0; failures = result.1; selected = Set(notes.map(\.id))
        status = "导入 \(notes.count) 篇 · \(failures.count) 项未完成；仅保留在当前应用内存中"
    }
}

struct NotesView: View {
    @StateObject private var model = NotesModel()
    var body: some View {
        if AppPaths.ready {
            NotesFileView(model: model)
        } else {
            NotesContent(model: model, filesAvailable: false, importFiles: {}, exportNotes: { _ in }, clearDocuments: {})
        }
    }
}

struct NotesContent: View {
    @ObservedObject var model: NotesModel
    let filesAvailable: Bool
    let importFiles: () -> Void
    let exportNotes: (Bool) -> Void
    let clearDocuments: () -> Void
    @State private var confirmExport = false
    @State private var confirmRead = false
    @State private var markdown = false
    @State private var query = ""
    private var visible: [ImportedNote] {
        model.notes.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    FeatureHeader(symbol: "note.text", title: "文字，妥善留存", detail: "直接读取 Apple Notes 未锁定正文，批量留存为 TXT / Markdown。")
                    Text(model.status).font(.footnote).foregroundStyle(.secondary)
                    Button { confirmRead = true } label: { Label("读取 Apple Notes", systemImage: "note.text.badge.plus") }
                    Button(action: importFiles) { Label("或选择文本文件", systemImage: "folder.badge.plus") }.disabled(!filesAvailable)
                    if !filesAvailable { FileUIUnavailableNotice() }
                    if !model.notes.isEmpty { Button("清除内存中的当前批次", role: .destructive) { model.clear(); clearDocuments() } }
                    if model.busy { ProgressView("正在创建只读快照并解析…") }
                }
                Section("导出设置") {
                    Picker("文件格式", selection: $markdown) { Text("TXT").tag(false); Text("Markdown").tag(true) }.pickerStyle(.segmented).disabled(!filesAvailable)
                    Text("导出 UTF-8 原文；Markdown 不自动重建表格或富文本。每次选择文件会替换当前批次，不修改来源。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("已导入 · \(model.notes.count) 篇") {
                    if model.notes.isEmpty {
                        EmptyCard(symbol: "doc.text", title: "从一篇文字开始", detail: "点「读取 Apple Notes」创建内存快照并提取正文。需要有效的 TrollStore 跨沙盒权限；也可导入自己的文本文件。")
                    } else {
                        HStack {
                            Button("选择结果") { model.selected.formUnion(visible.map(\.id)) }
                            Spacer()
                            Button("取消全选") { model.selected.removeAll() }
                        }
                        if visible.isEmpty { Text("没有匹配的文字").foregroundStyle(.secondary) }
                        ForEach(visible) { note in
                            Button {
                                if !model.selected.insert(note.id).inserted { model.selected.remove(note.id) }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: model.selected.contains(note.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(note.title).font(.headline)
                                        Text(note.text.isEmpty ? "空白文本" : note.text).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }.foregroundStyle(.primary)
                            }.accessibilityLabel("\(note.title)，\(model.selected.contains(note.id) ? "已选中" : "未选中")")
                        }
                    }
                }
                if !model.failures.isEmpty {
                    Section("未导入项目") { ForEach(Array(model.failures.enumerated()), id: \.offset) { _, message in Text(message).font(.footnote) } }
                }
                Section("功能边界") {
                    Text("只读提取 iOS 16 常规未锁定笔记正文，不是全库备份。锁定、未下载或无法解析项目会跳过；不解锁、不下载附件，不重建表格、扫描件、手写或富文本。正文中的嵌入对象占位符原样保留。请核对跳过计数。退出后需重新读取。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.listStyle(.insetGrouped)
                .disabled(model.busy)
                .navigationTitle("备忘录导出")
                .searchable(text: $query, prompt: "搜索标题或正文")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("导出 \(model.selected.count) 篇") { confirmExport = true }.disabled(!filesAvailable || model.selected.isEmpty || model.busy)
                    }
                }
                .confirmationDialog("读取 Apple Notes？", isPresented: $confirmRead, titleVisibility: .visible) {
                    Button("只读读取未锁定正文") { Task { await model.loadAppleNotes() } }
                } message: {
                    Text("将定位 Notes 专用容器并创建内存一致性快照，不修改备忘录。最多 1000 篇 / 16 MiB 正文，数据库上限 128 MiB；读取成功会替换当前批次。尚未经 iOS 16.6 真机验证。")
                }
                .confirmationDialog("导出所选文本？", isPresented: $confirmExport, titleVisibility: .visible) {
                    Button("选择保存位置") {
                        exportNotes(markdown)
                    }
                } message: { Text("共 \(model.selected.count) 篇（包括搜索隐藏项）。文本可能包含隐私；选择 iCloud 等位置可能由系统同步。") }
        }
    }
}
