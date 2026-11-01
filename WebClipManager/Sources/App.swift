import SwiftUI
import UIKit

@MainActor
final class Model: ObservableObject {
    @Published var scan = Scan()
    @Published var selected = Set<String>()
    @Published var busy = false
    @Published var status = "尚未读取设备目录"
    @Published var readState = "notRead"
    @Published var accessSnapshot: AccessSnapshot?
    @Published var accessFailure: AccessError?
    @Published var results: [ItemResult] = []
    @Published var showResults = false
    let repository = Repository()

    func refresh() async {
        guard !busy else { return }
        StartupLog.record("S9_REFRESH_ENTERED")
        busy = true
        readState = "reading"
        defer { busy = false }
        accessFailure = nil
        accessSnapshot = await repository.accessDiagnostics()
        do {
            scan = try await repository.scan()
            accessFailure = scan.firstFailure
            StartupLog.record("S11_SCAN_RETURNED")
            readState = scan.issues.isEmpty ? "readable" : "partial"
            selected.formIntersection(Set(scan.clips.map(\.id)))
            status = "已读取 \(scan.clips.count) 项；\(scan.issues.count) 项读取警告"
            if !scan.issues.isEmpty { results = scan.issues; showResults = true }
        } catch {
            StartupLog.record("S11_SCAN_THROWN")
            readState = "failed"
            scan = Scan()
            selected.removeAll()
            let failure = AccessError.capture(error)
            accessFailure = failure
            status = "读取失败：\(failure.summary)。请导出诊断定位；错误码本身不能区分 POSIX 与 MAC/sandbox 拒绝，不代表目录为空。"
        }
    }

    func backup() async -> Data? {
        guard !busy, !selected.isEmpty else { return nil }
        busy = true
        defer { busy = false }
        do {
            let backup = try await repository.backup(ids: Array(selected))
            results = backup.results
            status = "备份已准备，尚未保存；失败项目见逐项结果"
            return backup.data
        } catch {
            results = [ItemResult(id: "备份", message: error.localizedDescription)]
            showResults = true
            return nil
        }
    }

    func delete() async {
        guard !busy else { return }
        busy = true
        results = await repository.delete(ids: Array(selected))
        busy = false
        showResults = true
    }
}

struct ManagerView: View {
    @ObservedObject var model: Model
    var body: some View {
        if AppPaths.ready {
            ManagerFileView(model: model)
        } else {
            ManagerContent(model: model, filesAvailable: false, exportBackup: {})
        }
    }
}

struct ManagerContent: View {
    @ObservedObject var model: Model
    let filesAvailable: Bool
    let exportBackup: () -> Void
    @State private var query = ""
    @State private var duplicatesOnly = false
    @State private var fullscreenOnly = false
    @State private var confirmBackup = false
    @State private var confirmDelete = false

    private var visible: [Clip] {
        let duplicateIDs = Repository.duplicateIDs(model.scan.clips)
        return model.scan.clips.filter {
            (!duplicatesOnly || duplicateIDs.contains($0.id)) &&
            (!fullscreenOnly || $0.fullScreen) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) ||
             $0.url.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FeatureHeader(symbol: "square.grid.2x2", title: "主屏幕书签，一目了然", detail: "本地浏览与备份，不访问 Safari 数据。")
                    Text(model.status).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    if !filesAvailable { FileUIUnavailableNotice() }
                    DisclosureGroup("删除验证进度") {
                        Text("当前构建不执行删除。等待 iOS 16.6 真机接口与系统行为验证，不代表永久无法实现。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.busy { ProgressView("正在读取…") }
                }
                Section("筛选与选择") {
                    Toggle("仅重复网址（完全相同）", isOn: $duplicatesOnly)
                    Toggle("仅全屏 WebClip", isOn: $fullscreenOnly)
                    HStack {
                        Button("选择当前结果") { model.selected.formUnion(visible.map(\.id)) }
                        Spacer()
                        Button("清空选择") { model.selected.removeAll() }
                    }
                    Text("显示 \(visible.count) 项 · 共选 \(model.selected.count) 项（含隐藏项）")
                        .font(.caption)
                }.disabled(model.busy)
                Section("WebClips") {
                    ForEach(visible) { clip in
                        Button {
                            if !model.selected.insert(clip.id).inserted { model.selected.remove(clip.id) }
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: model.selected.contains(clip.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Color.accentColor)
                                ClipIcon(data: clip.icon)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(clip.title.isEmpty ? "未命名书签" : clip.title).font(.headline)
                                    Text(clip.url.isEmpty ? "未提供 URL" : clip.url).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    Text("\(clip.fullScreen ? "全屏" : "浏览器")\(clip.removalDisallowed ? " · 标记禁止移除" : "")")
                                        .font(.caption2)
                                }
                            }.foregroundStyle(.primary)
                        }.disabled(model.busy)
                            .accessibilityLabel("\(clip.title)，\(model.selected.contains(clip.id) ? "已选中" : "未选中")")
                    }
                    if visible.isEmpty {
                        EmptyCard(symbol: "square.grid.2x2", title: model.scan.clips.isEmpty ? "还没有可显示的书签" : "没有匹配结果", detail: model.scan.clips.isEmpty ? "请查看读取状态，或前往诊断页检查权限。读取失败不代表没有书签。" : "尝试调整搜索词，或关闭重复与全屏筛选。")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("书签管理")
            .searchable(text: $query, prompt: "名称、URL 或目录标识")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink { DiagnosticsView(model: model) } label: { Label("诊断", systemImage: "stethoscope") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { StartupLog.record("S8_SCAN_BUTTON"); Task { await model.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                        .disabled(model.busy)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("导出备份") { confirmBackup = true }
                        .disabled(!filesAvailable || model.busy || model.selected.isEmpty)
                    Spacer()
                    Button("删除（不可用）", role: .destructive) { confirmDelete = true }
                        .disabled(model.busy || model.selected.isEmpty)
                    Button { model.showResults = true } label: { Label("逐项结果", systemImage: "list.bullet.rectangle") }
                }
            }
            .onAppear { StartupLog.record("S6_MANAGER_ON_APPEAR_NO_SCAN") }
            .confirmationDialog("导出所选 \(model.selected.count) 项？", isPresented: $confirmBackup, titleVisibility: .visible) {
                Button("生成本地备份", action: exportBackup)
            } message: {
                Text("备份包含原始 URL、图标和目录文件，可能包含敏感信息。部分失败会逐项列明；请保存到可信位置。此版本不提供恢复。")
            }
            .confirmationDialog("系统删除尚不可用", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("查看所选项目的拒绝原因") { Task { await model.delete() } }
            } message: {
                Text("不会执行删除，也不会仅移除目录冒充系统删除。请从主屏幕手动删除；受管理项目可能需联系管理员。")
            }
            .sheet(isPresented: $model.showResults) {
                NavigationStack {
                    List(model.results) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.id).font(.caption).textSelection(.enabled)
                            Text(item.message)
                        }
                    }.navigationTitle("逐项结果")
                        .toolbar { Button("完成") { model.showResults = false } }
                }
            }
        }
    }
}

private struct ClipIcon: View {
    let data: Data?
    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "globe").resizable().scaledToFit().padding(6)
            }
        }.frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}
