import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ObjectiveC.runtime

struct FeatureHeader: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8)
    }
}

struct EmptyCard: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 16)
    }
}

struct RootView: View {
    @StateObject private var model = Model()
    var body: some View {
        TabView {
            ManagerView(model: model).tabItem { Label("书签管理", systemImage: "square.grid.2x2") }
            NotesView().tabItem { Label("备忘录导出", systemImage: "note.text") }
        }.tint(.teal)
            .onAppear { StartupLog.record("S6_ROOT_ON_APPEAR") }
    }
}

struct DiagnosticReport: Codable {
    let schemaVersion: Int
    let osVersion: String
    let webClipsReadState: String
    let uiWebClipClassPresent: Bool
    let selectorPresence: [String: Bool]
    let deletionEnabled: Bool

    static func capture(readState: String, osVersion: String) -> DiagnosticReport {
        let cls: AnyClass? = NSClassFromString("UIWebClip")
        var presence: [String: Bool] = [:]
        // Metadata inspection only. Never allocate UIWebClip or invoke these methods.
        for name in ["removeFromDisk", "requestIconUpdateInSpringBoard"] {
            presence["instance." + name] = cls.map { class_getInstanceMethod($0, NSSelectorFromString(name)) != nil } ?? false
        }
        presence["class.webClipWithIdentifier:"] = cls.map {
            class_getClassMethod($0, NSSelectorFromString("webClipWithIdentifier:")) != nil
        } ?? false
        let allowed = ["notRead", "reading", "readable", "partial", "failed"]
        return DiagnosticReport(schemaVersion: 1, osVersion: osVersion,
            webClipsReadState: allowed.contains(readState) ? readState : "notRead",
            uiWebClipClassPresent: cls != nil, selectorPresence: presence, deletionEnabled: false)
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: Model
    @State private var report: DiagnosticReport?
    @State private var exporting = false
    @State private var document = BackupDocument()
    @State private var feedback = ""
    private func refresh() {
        report = DiagnosticReport.capture(readState: model.readState, osVersion: UIDevice.current.systemVersion)
    }
    var body: some View {
        List {
            Section {
                FeatureHeader(symbol: "stethoscope", title: "首次测试，从只读开始", detail: "检查系统版本、目录读取状态与运行时接口，不执行删除。")
                Button("更新接口诊断") { refresh() }
                Button("重新读取 WebClips") { Task { await model.refresh(); refresh() } }.disabled(model.busy)
            }
            if let report {
                Section("脱敏报告预览") {
                    Text("iOS \(report.osVersion)")
                    Text("WebClips：\(report.webClipsReadState)")
                    Text("UIWebClip：\(report.uiWebClipClassPresent ? "存在" : "未发现")")
                    ForEach(report.selectorPresence.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key).font(.footnote).textSelection(.enabled)
                            Text(report.selectorPresence[key] == true ? "存在" : "未发现").foregroundStyle(.secondary)
                        }
                    }
                    Text("删除执行：禁用")
                }
                Section {
                    Button { do { document = BackupDocument(data: try report.encoded()); exporting = true } catch { feedback = "报告编码失败" } } label: {
                        Label("导出脱敏诊断 JSON", systemImage: "square.and.arrow.up")
                    }
                    Text("仅含上方状态和报告格式版本，不含 URL、标题、目录标识、设备标识、数量或错误原文。接口存在不等于权限或完整删除语义已验证；未发现也不证明永久不可用。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !feedback.isEmpty { Text(feedback).font(.footnote) }
                }
            }
        }.listStyle(.insetGrouped).navigationTitle("诊断").task { refresh() }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "WebClip-diagnostics.json") { result in
                switch result {
                case .success: feedback = "诊断已导出"
                case .failure: feedback = "诊断导出未完成"
                }
                document = BackupDocument()
            }
    }
}
