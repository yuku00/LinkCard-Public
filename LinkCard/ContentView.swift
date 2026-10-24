// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import PhotosUI

@main
struct LinkCardApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

/// UI intent gate only. CoreNFC still performs all device/mailbox checks.
/// Both confirmation and direct-send consume the same click-time frame once.
struct SendRequestState {
    enum Decision: Equatable { case confirm, send }
    private var frame: Data?
    private(set) var dispatched = false
    mutating func prepare(frame: Data?, busy: Bool, loading: Bool, previewPending: Bool,
                          requiresConfirmation: Bool) -> Decision? {
        guard !dispatched, self.frame == nil, !busy, !loading, !previewPending,
              let frame, frame.count == 5000 else { return nil }
        self.frame = frame
        return requiresConfirmation ? .confirm : .send
    }
    mutating func takeFrame(busy: Bool, loading: Bool, previewPending: Bool) -> Data? {
        guard !dispatched, let snapshot = frame else { return nil }
        frame = nil
        guard !busy, !loading, !previewPending, snapshot.count == 5000 else { return nil }
        dispatched = true
        return snapshot
    }
    mutating func cancel() { frame = nil }
    mutating func finish() { dispatched = false }
}

final class PreviewActivity: ObservableObject {
    // Reference state is read at execution time, never from an old View closure.
    var active = false
}

struct ContentView: View {
    @StateObject private var nfc = NFCService()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected: PhotosPickerItem?
    @State private var importedSelection: PhotosPickerItem?
    @State private var photoPickerPresented = false
    @State private var photo: UIImage?
    @State private var source = 4
    @State private var fill = true
    @State private var turns = 0
    @State private var threshold = 120.0
    // Editor preferences are session-only; a fresh editor uses photo dithering.
    @State private var dither = true
    @State private var text = "留一点空间，\n给重要的事。"
    @State private var qr = "https://example.com"
    @State private var fontSize = 20.0
    @State private var testKind = 3
    @State private var dateStyle = 0
    @State private var cardDate = Date()
    @State private var tasks = "出门走一走\n读十页书\n给自己留一点时间"
    @State private var rendered: RenderedCard?
    @State private var renderError: String?
    @StateObject private var previewActivity = PreviewActivity()
    @State private var previewTask: Task<Void, Never>?
    @State private var previewPending = false
    @State private var previewDirty = true
    @State private var loading = false
    @State private var confirmSend = false
    @State private var showLogs = false
    @StateObject private var wallpaper = WallpaperStore()
    @StateObject private var cardBlur = MistBlurStore()
    @StateObject private var library = LocalCardLibrary()
    @StateObject private var ble = PCRBluetooth()
    @StateObject private var workbench: WorkbenchState
    @StateObject private var fusion: FusionState
    @Environment(\.dynamicTypeSize) private var typeSize
    init(workbench: WorkbenchState = WorkbenchState(), fusion: FusionState = FusionState()) {
        _fusion = StateObject(wrappedValue: fusion)
        _workbench = StateObject(wrappedValue: workbench)
    }
    @State private var keyboardVisible = false
    @AppStorage("nfc.confirmBeforeSend.v1") private var confirmBeforeSend = true
    @State private var sendRequest = SendRequestState()
    private let accent = MistStyle.accent
    private let templates = [(4, "日期", "calendar"), (2, "便签", "text.alignleft"),
                             (0, "照片", "photo"), (1, "二维码", "qrcode"),
                             (5, "清单", "checklist"), (3, "测试图", "square.grid.2x2")]

    var body: some View {
        let _ = { fusion.rootBodyCount += 1 }()
        FusionShell(state: fusion, workbench: workbench, wallpaper: wallpaper,
                    library: library, keyboard: keyboardVisible, busy: nfc.busy) {
            Group {
                switch workbench.tab {
                case .create: creationPage
                case .library: LocalCardLibraryView(library: library)
                case .device: PCRDeviceView(ble: ble)
                case .settings: settings
                }
            }
        }
        .coordinateSpace(name: "workbench.shell")
        .onPreferenceChange(WorkbenchFrames.self) { frames in
            workbench.frames = frames
            // Diagnostic geometry is non-published; never feed it into root State.
        }
        .bleDiscoveryHost(ble)
        .foregroundStyle(MistStyle.ink).tint(MistStyle.link)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onReceive(nfc.$status) { _ in
            // Includes unavailable/invalid-start failures that never set busy.
            if !nfc.busy && sendRequest.dispatched { sendRequest.finish() }
        }
        .photosPicker(isPresented: $photoPickerPresented, selection: $selected, matching: .images)
        .confirmationDialog("发送到墨水屏？", isPresented: $confirmSend, titleVisibility: .visible) {
            Button("通过 NFC 发送") { dispatchPreparedSend() }
            Button("取消", role: .cancel) { sendRequest.cancel() }
        } message: {
            Text("仅发送到兼容 ST25DV Link-Card，不使用 PCR 蓝牙。请持续供电并贴合手机顶部；失败或取消后断电重启。")
        }
        .task { previewActivity.active = scenePhase == .active; updatePreview() }
        .task(id: selected) { await loadPhoto() }
        .onChange(of: source) { _ in updatePreview() }
        .onChange(of: fill) { _ in updatePreview() }
        .onChange(of: turns) { _ in updatePreview() }
        .onChange(of: threshold) { _ in updatePreview() }
        .onChange(of: dither) { _ in updatePreview() }
        .onChange(of: text) { _ in updatePreview() }
        .onChange(of: qr) { _ in updatePreview() }
        .onChange(of: fontSize) { _ in updatePreview() }
        .onChange(of: testKind) { _ in updatePreview() }
        .onChange(of: dateStyle) { _ in updatePreview() }
        .onChange(of: cardDate) { _ in updatePreview() }
        .onChange(of: tasks) { _ in updatePreview() }
        .onChange(of: scenePhase) { phase in
            previewActivity.active = phase == .active
            if phase != .active { previewTask?.cancel(); previewTask = nil }
            else if previewDirty { updatePreview() }
            if phase == .background { nfc.cancel() }
        }
        .sheet(isPresented: $showLogs) {
            NavigationStack {
                ScrollView {
                    Text(nfc.logs.isEmpty ? "还没有会话日志" : nfc.logs.joined(separator: "\n"))
                        .font(.caption.monospaced()).textSelection(.enabled).padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.navigationTitle("诊断日志")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) { ShareLink(item: nfc.logs.joined(separator: "\n")) }
                        ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { showLogs = false } }
                    }
            }
        }
        // Apply outside all content-producing modifiers, including the tab inset.
        // An environment on the inner ZStack does not reach safeAreaInset siblings.
        .environmentObject(cardBlur)
        .buttonStyle(MistActionStyle())
    }

    private var creationPage: some View {
        GeometryReader { geometry in
            let transferLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !keyboardVisible {
                        HStack { Spacer(); preview(width: geometry.size.width, availableHeight: geometry.size.height); Spacer() }
                            .recordWorkbenchFrame("create.preview.row")
                        Text("200 × 200 · 单色电子纸").font(.caption.monospacedDigit())
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .recordWorkbenchFrame("create.caption")
                    }
                    transferLayout {
                        Label("NFC · Link-Card", systemImage: "wave.3.right").font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        Button { prepareSend() } label: {
                            Label("发送", systemImage: "square.and.arrow.up").frame(minHeight: 44)
                        }.accessibilityLabel("发送到墨水屏").accessibilityIdentifier("create.send")
                            .disabled(nfc.busy || sendRequest.dispatched || confirmSend || loading || previewPending || rendered == nil)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(templates, id: \.0) { item in
                                Button { source = item.0 } label: {
                                    Label(item.1, systemImage: item.2).font(.subheadline)
                                        .padding(.horizontal, 12).frame(minHeight: 44)
                                        .background(source == item.0 ? accent.opacity(0.16) : Color.clear, in: Capsule())
                                }.buttonStyle(.plain).disabled(nfc.busy)
                                    .accessibilityAddTraits(source == item.0 ? .isSelected : [])
                            }
                        }
                    }
                    editor.disabled(nfc.busy)
                    if keyboardVisible { Button("完成编辑") { dismissKeyboard() }.frame(minHeight: 44) }
                    transferStatus
                }
                // A vertical ScrollView must not inherit a wide child's ideal width.
                // Keep the readable column bounded; allow large text to grow vertically.
                .frame(width: max(0, geometry.size.width - 32), alignment: .leading)
                .recordWorkbenchFrame("create.column")
                .padding(16)
            }.scrollDismissesKeyboard(.interactively)
        }
    }

    private func preview(width: CGFloat, availableHeight: CGFloat) -> some View {
        let side = min(WorkbenchState.previewSide(width: width), max(20, availableHeight - 52))
        return Button { choosePhoto() } label: {
            Group {
                if let rendered = rendered {
                    Image(uiImage: rendered.image).resizable().interpolation(.none)
                        .accessibilityLabel("200 乘 200 单色预览，请检查是否裁切")
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.on.rectangle.angled").font(.largeTitle)
                        Text(loading ? "正在载入…" : "选择内容，开始制卡").font(.caption)
                    }.foregroundStyle(Color.black).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white)
                }
            }
            .frame(width: side, height: side)
            .overlay(Rectangle().stroke(Color.black.opacity(0.12), lineWidth: 1))
            .padding(10)
            .background { MistSurface(id: "create.preview", radius: 14) }
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(nfc.busy || sendRequest.dispatched || loading || photoPickerPresented)
        .accessibilityLabel("选择照片作为墨水屏内容")
        .accessibilityHint("轻点打开照片选择；取消将保留当前内容")
        .accessibilityIdentifier("create.preview")
    }

    private func prepareSend() {
        // A dismissed confirmation may leave a snapshot; a new explicit click
        // replaces it, but never clears the synchronous dispatched latch.
        if !confirmSend { sendRequest.cancel() }
        guard let decision = sendRequest.prepare(frame: rendered?.frame, busy: nfc.busy,
            loading: loading, previewPending: previewPending,
            requiresConfirmation: confirmBeforeSend) else { return }
        switch decision {
        case .confirm: confirmSend = true
        case .send: dispatchPreparedSend()
        }
    }
    private func dispatchPreparedSend() {
        guard let frame = sendRequest.takeFrame(busy: nfc.busy, loading: loading,
                                                previewPending: previewPending) else { return }
        nfc.send(frame: frame)
    }

    private var transferStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if nfc.busy {
                ProgressView(value: Double(nfc.progress), total: 25)
                Button("取消会话", role: .destructive) { nfc.cancel() }.frame(minHeight: 44)
            }
            Text(nfc.status).font(.footnote).textSelection(.enabled)
                .accessibilityIdentifier("nfc.status")
            DisclosureGroup("传输详情") {
                Text("25/25 是发送完成，不是屏幕确认。继续供电至少 3 秒并观察实卡；失败或取消后断电重启。日志在设置 → 高级诊断。")
                    .font(.footnote).padding(.top, 8)
            }
        }.padding(12).background { MistSurface(id: "create.transfer", radius: 14) }
    }
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @ViewBuilder private var editor: some View {
        switch source {
        case 0:
            Button { choosePhoto() } label: { Label("选择照片", systemImage: "photo.badge.plus") }
                .disabled(nfc.busy || sendRequest.dispatched || loading || photoPickerPresented)
                .accessibilityIdentifier("create.choosePhoto")
            if loading { ProgressView("正在读取照片…") }
            Picker("方形构图", selection: $fill) { Text("居中填充").tag(true); Text("完整适应").tag(false) }.pickerStyle(.menu)
            Button("顺时针旋转 90°") { turns = (turns+1)%4 }
            Toggle("细腻抖动", isOn: $dither).accessibilityIdentifier("create.dither")
            VStack(alignment: .leading) { Text("黑白阈值 · \(Int(threshold))"); Slider(value: $threshold, in: 0...254, step: 1).accessibilityLabel("黑白阈值") }
            hint("填充会裁掉边缘，适应保留白边。抖动适合照片；文字建议使用清晰的纯黑白。")
        case 1:
            TextField("链接或文字", text: $qr, axis: .vertical).lineLimit(2...5)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            hint("本地生成，最多 160 个 UTF-8 字节。保留四模块静区；发送前后请用另一台设备扫码验证。")
        case 2:
            TextEditor(text: $text).scrollContentBackground(.hidden).frame(minHeight: 140).accessibilityLabel("便签文字")
            VStack(alignment: .leading) { Text("字号 · \(Int(fontSize))"); Slider(value: $fontSize, in: 12...32, step: 1).accessibilityLabel("卡片文字字号") }
            hint("超出画布的文字会裁切，请检查预览。内容仅在本次运行保留。")
        case 4:
            Picker("版式", selection: $dateStyle) {
                Text("日期").tag(0); Text("日期与星期").tag(1); Text("月历").tag(2)
            }.pickerStyle(.menu)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("卡片日期")
                    DatePicker("卡片日期", selection: $cardDate, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }
            } else {
                DatePicker("卡片日期", selection: $cardDate, displayedComponents: .date).environment(\.locale, Locale(identifier: "zh_CN"))
            }
            Button { cardDate = Date(); updatePreview() } label: { Label("使用今天", systemImage: "arrow.clockwise") }
            hint("按手机当前本地时区生成静态图。只有每次手机发送才会更新，卡片不会自动走时或翻日。跨日后可点「使用今天」。")
        case 5:
            TextEditor(text: $tasks).scrollContentBackground(.hidden).frame(minHeight: 140).accessibilityLabel("任务清单，每行一项")
            hint("每行一项，最多显示 5 项。发送的是静态清单图，不支持在卡片上交互勾选；长文字会截断，请检查预览。")
        default:
            Picker("图案", selection: $testKind) {
                Text("全黑").tag(0); Text("全白").tag(1); Text("棋盘").tag(2); Text("方向标记").tag(3)
            }
            hint("用方向标记检查上下方向和边缘，不改变稳定的编码与分包。")
        }
        if let renderError = renderError { Label(renderError, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red) }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(MistStyle.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func choosePhoto() {
        guard !nfc.busy, !sendRequest.dispatched, !loading, !photoPickerPresented else { return }
        // Reset only the picker selection, never photo/editor/rendered content.
        // This permits choosing the same asset again after switching templates.
        selected = nil
        photoPickerPresented = true
    }

    @MainActor private func loadPhoto() async {
        guard let item = selected, !nfc.busy, !sendRequest.dispatched else { return }
        if item == importedSelection {
            source = 0; updatePreview() // Reuse a successfully decoded selection.
            return
        }
        // Opening/cancelling the picker does not clear the current template or
        // frame. Commit only after a selected photo has loaded and decoded.
        loading = true
        defer { loading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw CardError.message("未能载入照片") }
            try Task.checkCancellation()
            guard selected == item, !nfc.busy, !sendRequest.dispatched else { return }
            let nextPhoto = try CardRenderer.photo(data: data)
            photo = nextPhoto; importedSelection = item
            source = 0; updatePreview()
        } catch is CancellationError { }
          catch { renderError = error.localizedDescription }
    }

    private func updatePreview() {
        previewTask?.cancel(); previewTask = nil
        previewDirty = true; previewPending = true
        guard previewActivity.active else { return }
        previewTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 60_000_000) }
            catch { return }
            guard !Task.isCancelled, previewActivity.active else { return }
            renderPreviewNow()
            previewPending = false
        }
    }

    // UIKit drawing remains main-actor confined; coalesce rapid editor changes, not touch feedback.
    @MainActor private func renderPreviewNow() {
        guard previewActivity.active else { return }
        previewDirty = false
        workbench.renderCount += 1
        do {
            let image: UIImage
            switch source {
            case 0:
                guard let photo = photo else { rendered = nil; renderError = "请选择照片"; return }
                image = CardRenderer.compose(photo, fill: fill, turns: turns)
            case 1: image = try CardRenderer.qr(qr)
            case 2: image = CardRenderer.note(text, size: fontSize)
            case 4: image = CardRenderer.dateCard(cardDate, style: dateStyle)
            case 5: image = CardRenderer.checklist(tasks)
            default: image = CardRenderer.test(testKind)
            }
            rendered = try CardRenderer.render(image, threshold: source == 0 ? threshold : 120, dither: source == 0 && dither)
            renderError = nil
        } catch { rendered = nil; renderError = error.localizedDescription }
    }

    private var settings: some View {
        MistPage("设置", subtitle: "自己的壁纸，熟悉的工具。") {
            WallpaperSettings(store: wallpaper)
            MistBlurSettings(library: library)
            MistPanel(id: "settings.about") {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Link-Card", systemImage: "rectangle.portrait").font(.title2.bold())
                    Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · 构建 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")").font(.subheadline.monospacedDigit())
                    Text("离线创作与本地卡包，前台连接你的设备。")
                        .font(.subheadline).foregroundStyle(MistStyle.secondary)
                }
            }
            MistPanel(id: "settings.reminders") {
                DisclosureGroup("发送前的小提醒") {
                  VStack(alignment: .leading, spacing: 12) {
                    Toggle("发送前确认", isOn: $confirmBeforeSend)
                        .accessibilityIdentifier("send.confirmBeforeSend")
                    Text("关闭后，点击发送会直接启动系统 NFC 扫描；只跳过本 App 的确认，不会隐藏系统 NFC 界面或跳过权限、设备型号与邮箱检查。")
                        .font(.footnote).foregroundStyle(MistStyle.secondary)
                    Label("持续供电，再贴合手机顶部", systemImage: "wave.3.right")
                    Text("你这张实卡：先持续按住远离 USB-C 的 A 电源键，再持续按住滚轮。刷新结束前保持供电与贴合。")
                        .font(.subheadline).foregroundStyle(MistStyle.secondary)
                    Text("日期和清单都是静态图；每次发送才更新。卡包里的备份文件不会发送到设备。")
                        .font(.subheadline).foregroundStyle(MistStyle.secondary)
                  }.padding(.top, 8)
                }
            }
            MistPanel(id: "settings.diagnostics") {
                DisclosureGroup("高级诊断与安全说明") {
                    VStack(alignment: .leading, spacing: 16) {
                        Button { nfc.identify() } label: { Label("新设备检测 · 只读 NFC 型号", systemImage: "wave.3.right") }
                            .disabled(nfc.busy || loading).frame(minHeight: 44)
                        Text("可选诊断，不是发送前置步骤。仅读取型号与邮箱状态，不写配置、不发送图像。")
                        if let identity = nfc.identity { Text(identity.summary).font(.caption.monospaced()).textSelection(.enabled) }
                        Text(nfc.status).textSelection(.enabled)
                        if nfc.busy { Button("取消会话", role: .destructive) { nfc.cancel() } }
                        Button("查看与分享 NFC 日志") { showLogs = true }.frame(minHeight: 44)
                        Text("仅 ISO15693；核对 ST 厂商与已知 ST25DV 型号，检查邮箱空闲、启用且没有丢消息标志。芯片识别不等于固件兼容证明。未知型号停止，不自动开启持久配置。")
                        Text("稳定路径保留 flags=02、5000 字节编码、25×200 分包、消费确认与动态邮箱切换；不发三字节复位头，不自动重试。25/25 不是屏幕 ACK。")
                        Text("BLE 名称与服务只是线索，不是认证。未知协议不发送命令，不寻卡、不写卡、不刷固件；跨页面保持连接，真正退到后台才停止。")
                        Text("照片和卡片本地处理；壁纸不上传、不加入系统备份。仅主动分享才导出卡包。NFC 日志只在本次运行保留，分享前请审查。")
                        Text("本版构建与源码回归不能代替真机验收。需要实测 iOS 16、动态字体、降低透明度、键盘、壁纸与实际设备。")
                    }.font(.footnote).foregroundStyle(MistStyle.secondary).padding(.top, 14)
                }
            }
            MistPanel(id: "settings.licenses") {
                DisclosureGroup("协议来源与许可") {
                    VStack(alignment: .leading, spacing: 16) {
                        Link("稚晖君 L-ink_Card", destination: URL(string: "https://github.com/peng-zhihui/L-ink_Card")!)
                        Link("明明 Link-Card 改进版", destination: URL(string: "https://oshwhub.com/dz_DIY_mingming/link_upgrade")!)
                        Text("独立实现 · GPL-3.0-or-later。协议依据 APK 静态分析与公开 HEX 交叉核对，保留来源报告。")
                    }.font(.footnote).padding(.top, 14)
                }
            }
        }
    }
}
