import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { DocumentUIProbe.record("document.types"); return [.data] }
    static var writableContentTypes: [UTType] { DocumentUIProbe.record("document.types"); return [.data, .json] }
    var data: Data
    init(data: Data = Data()) { DocumentUIProbe.record("backup.document"); self.data = data }
    init(configuration: ReadConfiguration) throws {
        DocumentUIProbe.record("document.read")
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct NoteExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { DocumentUIProbe.record("document.types"); return [.plainText] }
    static var writableContentTypes: [UTType] { DocumentUIProbe.record("document.types"); return [.plainText, UTType(filenameExtension: "md") ?? .plainText] }
    var text: String
    var filename: String
    init(text: String, filename: String) { DocumentUIProbe.record("note.document"); self.text = text; self.filename = filename }
    init(configuration: ReadConfiguration) throws {
        DocumentUIProbe.record("document.read")
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        self.text = text
        filename = configuration.file.preferredFilename ?? "备忘录.txt"
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let wrapper = FileWrapper(regularFileWithContents: Data(text.utf8))
        wrapper.preferredFilename = filename
        return wrapper
    }
}


// Debug-only construction evidence; Release has no counters or persistence.
enum DocumentUIProbe {
#if DEBUG
    private static let lock = NSLock()
    private static var events: [String: Int] = [:]
    static var snapshot: [String: Int] {
        lock.lock(); defer { lock.unlock() }; return events
    }
    static func reset() { lock.lock(); defer { lock.unlock() }; events = [:] }
#endif
    static func record(_ event: String) {
#if DEBUG
        lock.lock(); defer { lock.unlock() }; events[event, default: 0] += 1
#endif
    }
}

struct FileUIUnavailableNotice: View {
    var body: some View {
        Label("当前未验证专属文件容器，文件导入与导出不可用；仍可只读浏览。诊断可在启动首页复制。", systemImage: "info.circle")
            .font(.footnote).foregroundStyle(.secondary)
    }
}

@MainActor
private final class ManagerDocuments: ObservableObject {
    @Published var exporting = false
    @Published var document = BackupDocument()
    init() { DocumentUIProbe.record("manager.state") }
}

struct ManagerFileView: View {
    @ObservedObject var model: Model
    @StateObject private var files = ManagerDocuments()
    private var contentType: UTType {
        DocumentUIProbe.record("manager.types")
        return .data
    }
    var body: some View {
        let _ = DocumentUIProbe.record("manager.modifiers")
        ManagerContent(model: model, filesAvailable: true, exportBackup: {
            Task {
                if let data = await model.backup() {
                    files.document = BackupDocument(data: data)
                    files.exporting = true
                }
            }
        })
        .fileExporter(isPresented: $files.exporting, document: files.document, contentType: contentType,
                      defaultFilename: "WebClips-\(Int(Date().timeIntervalSince1970)).webclipbackup") { result in
            switch result {
            case .success: model.status = "系统文件导出完成；请查看逐项结果确认覆盖范围"
            case .failure(let error): model.status = "导出未完成：\(error.localizedDescription)"
            }
            files.document = BackupDocument()
            model.showResults = true
        }
    }
}

@MainActor
private final class NotesDocuments: ObservableObject {
    @Published var importing = false
    @Published var exporting = false
    @Published var markdown = false
    @Published var documents: [NoteExportDocument] = []
    init() { DocumentUIProbe.record("notes.state") }
}

struct NotesFileView: View {
    @ObservedObject var model: NotesModel
    @StateObject private var files = NotesDocuments()
    private var importTypes: [UTType] {
        DocumentUIProbe.record("notes.types")
        return [.plainText, UTType(filenameExtension: "md") ?? .plainText]
    }
    var body: some View {
        let _ = DocumentUIProbe.record("notes.modifiers")
        NotesContent(model: model, filesAvailable: true, importFiles: { files.importing = true }, exportNotes: { markdown in
            files.markdown = markdown
            files.documents = model.notes.filter { model.selected.contains($0.id) }.enumerated().map { index, note in
                NoteExportDocument(text: note.text, filename: NoteFiles.filename(note.title, index: index, markdown: markdown))
            }
            files.exporting = true
        }, clearDocuments: { files.documents = [] })
        .fileImporter(isPresented: $files.importing, allowedContentTypes: importTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await model.load(urls) }
            case .failure: model.status = "文件选择未完成；当前批次未改变"
            }
        }
        .fileExporter(isPresented: $files.exporting, documents: files.documents, contentType: files.markdown ? (UTType(filenameExtension: "md") ?? .plainText) : .plainText) { result in
            switch result {
            case .success(let urls): model.status = "系统导出器已保存 \(urls.count) 个文件；请到所选位置核对正文"
            case .failure: model.status = "导出未完成，原始文件与当前批次均未改变"
            }
            files.documents = []
        }
    }
}

@MainActor
private final class DiagnosticsDocuments: ObservableObject {
    @Published var exporting = false
    @Published var document = BackupDocument()
    @Published var feedback = ""
    init() { DocumentUIProbe.record("diagnostics.state") }
}

struct DiagnosticsFileView: View {
    @ObservedObject var model: Model
    @StateObject private var files = DiagnosticsDocuments()
    private var contentType: UTType {
        DocumentUIProbe.record("diagnostics.types")
        return .json
    }
    var body: some View {
        let _ = DocumentUIProbe.record("diagnostics.modifiers")
        DiagnosticsContent(model: model, filesAvailable: true, exportReport: { report in
            do {
                files.document = BackupDocument(data: try report.encoded())
                files.exporting = true
            } catch { files.feedback = "报告编码失败" }
        })
        .safeAreaInset(edge: .bottom) {
            if !files.feedback.isEmpty { Text(files.feedback).font(.footnote).padding().background(.regularMaterial) }
        }
        .fileExporter(isPresented: $files.exporting, document: files.document, contentType: contentType, defaultFilename: "WebClip-diagnostics.json") { result in
            switch result {
            case .success: files.feedback = "诊断已导出"
            case .failure: files.feedback = "诊断导出未完成"
            }
            files.document = BackupDocument()
        }
    }
}
