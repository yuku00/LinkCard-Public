import SwiftUI
import UIKit
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
    let build: String
    let fileAccess: AccessSnapshot?
    let readFailure: AccessError?
    let runtimePermissions: RuntimePermissions?
    let localPaths: LocalPathDiagnostics
    let notesRead: NotesReadDiagnostic

    static func capture(readState: String, osVersion: String, fileAccess: AccessSnapshot? = nil, readFailure: AccessError? = nil) -> DiagnosticReport {
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
        return DiagnosticReport(schemaVersion: 3, osVersion: osVersion,
            webClipsReadState: allowed.contains(readState) ? readState : "notRead",
            uiWebClipClassPresent: cls != nil, selectorPresence: presence, deletionEnabled: false,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            fileAccess: fileAccess, readFailure: readFailure,
            runtimePermissions: RuntimePermissions.capture(), localPaths: LocalPathDiagnostics.capture(),
            notesRead: NotesReadDiagnostic.capture())
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: Model
    var body: some View {
        if AppPaths.ready {
            DiagnosticsFileView(model: model)
        } else {
            DiagnosticsContent(model: model, filesAvailable: false, exportReport: { _ in })
        }
    }
}

struct DiagnosticsContent: View {
    @ObservedObject var model: Model
    @State private var report: DiagnosticReport?
    let filesAvailable: Bool
    let exportReport: (DiagnosticReport) -> Void
    private func refresh() {
        report = DiagnosticReport.capture(readState: model.readState, osVersion: UIDevice.current.systemVersion,
            fileAccess: model.accessSnapshot, readFailure: model.accessFailure)
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
                    Text("iOS \(report.osVersion) · build \(report.build)")
                    if let failure = report.readFailure { Text(failure.summary).font(.footnote).textSelection(.enabled) }
                    if let access = report.fileAccess {
                        Text("uid/euid：\(access.uid)/\(access.euid)")
                        ForEach(access.paths, id: \.path) { path in
                            Text("\(path.path) · open=\(path.openSucceeded ? "OK" : "failed") errno=\(path.openErrno)").font(.caption)
                        }
                    }
                    Text("WebClips：\(report.webClipsReadState)")
                    Text("UIWebClip：\(report.uiWebClipClassPresent ? "存在" : "未发现")")
                    ForEach(report.selectorPresence.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key).font(.footnote).textSelection(.enabled)
                            Text(report.selectorPresence[key] == true ? "存在" : "未发现").foregroundStyle(.secondary)
                        }
                    }
                    Text("Notes：\(report.notesRead.state)")
                    Text("专属数据路径：\(report.localPaths.dedicatedStorageReady ? "已验证" : "未验证，文件导入/导出禁用")")
                    if let runtime = report.runtimePermissions {
                        Text("自身权限 API：\(runtime.entitlementAPI) · Seatbelt API：\(runtime.sandboxAPI)")
                        ForEach(runtime.entitlements.keys.sorted(), id: \.self) { key in
                            Text("\(key)：\(runtime.entitlements[key] ?? "unknown") [\(runtime.expectedComparison[key] ?? "unknown")]").font(.caption)
                        }
                    }
                    DisclosureGroup("完整脱敏诊断（可选择文字）") {
                        Text((try? String(decoding: report.encoded(), as: UTF8.self)) ?? "编码失败").font(.caption).textSelection(.enabled)
                    }
                    Text("删除执行：禁用")
                }
                Section {
                    Button { exportReport(report) } label: {
                        Label("导出脱敏诊断 JSON", systemImage: "square.and.arrow.up")
                    }.disabled(!filesAvailable)
                    if !filesAvailable { FileUIUnavailableNotice() }
                    Text("实际自身签名九项白名单及期望比较、固定路径 Seatbelt 检查、专属本地路径匹配状态、Notes 读取状态；另含状态、构建号、uid/euid/gid/egid、固定系统路径的打开结果/errno/属主/模式、NSError 域与代码。不含书签 URL、标题、目录标识、设备标识、数量或错误原文。错误码不能单独证明是 POSIX 或 MAC/sandbox；接口存在不等于删除可用。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.listStyle(.insetGrouped).navigationTitle("诊断").task { refresh() }
    }
}
