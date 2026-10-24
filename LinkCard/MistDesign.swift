// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit
import PhotosUI
import ImageIO
import Combine

/// iOS 16 Material, not iOS 26 Liquid Glass. Wallpaper never enters card rendering.
enum MistStyle {
    static let accent = Color(red: 0.12, green: 0.36, blue: 0.68)
    static let link = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.60, green: 0.79, blue: 1, alpha: 1) : UIColor(red: 0.12, green: 0.36, blue: 0.68, alpha: 1) })
    static let ink = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.91, green: 0.95, blue: 1, alpha: 1) : UIColor(red: 0.10, green: 0.17, blue: 0.25, alpha: 1) })
    static let secondary = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.77, green: 0.83, blue: 0.90, alpha: 1) : UIColor(red: 0.26, green: 0.34, blue: 0.43, alpha: 1) })
}

struct MistPanel<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    private let id: String
    private let content: Content
    init(id: String, @ViewBuilder content: () -> Content) { self.id = id; self.content = content() }
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background { MistSurface(id: id) }
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(scheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.8), lineWidth: 1))
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.12 : 0.045), radius: 18, x: 0, y: 8)
            .foregroundStyle(MistStyle.ink)
    }
}

struct MistPage<Content: View>: View {
    let title: String
    let subtitle: String
    private let content: Content
    init(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.content = content()
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(subtitle).font(.subheadline).foregroundStyle(MistStyle.secondary)
                }.padding(.horizontal, 2).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                content
            }.padding(14).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively)
    }
}

final class WallpaperStore: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published var message: String?
    private var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Appearance", isDirectory: true).appendingPathComponent("wallpaper.jpg")
    }
    init() {
#if DEBUG
        // In-memory, local texture for full-window XCUITest only; no user file writes.
        if ProcessInfo.processInfo.arguments.contains("--uitest-texture") {
            image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 900)).image { context in
                for y in stride(from: 0, to: 900, by: 6) {
                    for x in stride(from: 0, to: 400, by: 6) {
                        ((x / 6 + y / 6) % 2 == 0 ? UIColor(red: 0.1, green: 0.2, blue: 0.5, alpha: 1) : UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)).setFill()
                        context.fill(CGRect(x: x, y: y, width: 6, height: 6))
                    }
                }
            }
            return
        }
#endif
        if let data = try? Data(contentsOf: url) { image = UIImage(data: data) }
    }
    func install(_ data: Data) throws {
        guard data.count <= 40 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1800,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw CardError.message("图片无法读取或超过 40 MiB，请选择较小的照片。") }
        let image = UIImage(cgImage: cg)
        guard let jpeg = image.jpegData(compressionQuality: 0.86) else { throw CardError.message("无法保存壁纸，请换一张照片。") }
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try jpeg.write(to: url, options: [.atomic, .completeFileProtection])
        self.image = image
    }
    func reset() {
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            image = nil
        } catch { message = "恢复默认失败，请解锁设备后再试。" }
    }
}

struct MistWallpaper: View {
    @ObservedObject var store: WallpaperStore
    @AppStorage("appearance.blur") private var blur = 18.0
    @AppStorage("appearance.veil") private var veil = 0.42
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: scheme == .dark ? [Color(red: 0.09, green: 0.17, blue: 0.25), Color(red: 0.13, green: 0.17, blue: 0.20), Color(red: 0.05, green: 0.09, blue: 0.14)] : [Color(red: 0.75, green: 0.86, blue: 0.96), Color(red: 0.93, green: 0.96, blue: 0.98), Color(red: 0.98, green: 0.96, blue: 0.91)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image = store.image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                        .blur(radius: min(40, max(0, blur)))
                }
                (scheme == .dark ? Color.black : Color.white).opacity(min(0.8, max(0.25, veil)))
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }.ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
    }
}

enum MainTab: Int, CaseIterable {
    case create, library, device, settings
    var title: String { ["制卡", "卡包", "设备", "设置"][rawValue] }
    var symbol: String { ["rectangle.portrait", "tray.full", "antenna.radiowaves.left.and.right", "slider.horizontal.3"][rawValue] }
}

struct MistTabBar: View {
    @Binding var selection: MainTab
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.headline)
                        Text(tab.title).font(.caption.weight(.semibold))
                    }.frame(maxWidth: .infinity).padding(.vertical, 7)
                        .foregroundStyle(selection == tab ? MistStyle.link : MistStyle.secondary)
                        .background(selection == tab ? MistStyle.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: typeSize.isAccessibilitySize ? 20 : 30))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selection == tab ? .isSelected : [])
                    .accessibilityLabel(tab.title)
            }
        }.padding(7)
            .background {
                MistSurface(id: "navigation.tabs", radius: typeSize.isAccessibilitySize ? 26 : 38)
            }
            .overlay(RoundedRectangle(cornerRadius: typeSize.isAccessibilitySize ? 26 : 38).strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: Color.black.opacity(0.08), radius: 16, y: 6)
            .frame(maxWidth: 560).padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
            .frame(maxWidth: .infinity)
    }
}

struct WallpaperSettings: View {
    @ObservedObject var store: WallpaperStore
    @AppStorage("appearance.blur") private var blur = 18.0
    @AppStorage("appearance.veil") private var veil = 0.42
    @State private var selected: PhotosPickerItem?
    @State private var loading = false
    var body: some View {
        MistPanel(id: "settings.wallpaper") {
            VStack(alignment: .leading, spacing: 18) {
                Label("壁纸与柔雾", systemImage: "photo.on.rectangle.angled").font(.headline)
                Text("让界面像你，也让卡片保持清晰。")
                    .font(.subheadline).foregroundStyle(MistStyle.secondary)
                PhotosPicker(selection: $selected, matching: .images) {
                    Label(store.image == nil ? "从照片选择壁纸" : "更换壁纸", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(MistActionStyle()).disabled(loading)
                if loading { ProgressView("正在处理壁纸…") }
                VStack(alignment: .leading) {
                    Text("背景壁纸模糊 · \(Int(blur))").font(.subheadline)
                    Slider(value: $blur, in: 0...40, step: 1).accessibilityLabel("背景壁纸模糊").accessibilityIdentifier("blur.wallpaper")
                }
                VStack(alignment: .leading) {
                    Text("柔光遮罩 · \(Int(veil * 100))%").font(.subheadline)
                    Slider(value: $veil, in: 0.25...0.8, step: 0.01).accessibilityLabel("柔光遮罩")
                }
                Button("恢复默认蓝白壁纸", role: .destructive) {
                    selected = nil; store.reset(); blur = 18; veil = 0.42
                }.frame(minHeight: 44).disabled(loading)
                Text("壁纸仅存本机，去除原图元数据，不进入卡片预览或发送内容。使用 iOS 16 原生 Material；不是 iOS 26 Liquid Glass。")
                    .font(.footnote).foregroundStyle(MistStyle.secondary)
            }
        }.task(id: selected) {
            guard let item = selected else { return }
            loading = true
            defer { loading = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CardError.message("未能载入壁纸，请重试。") }
                try Task.checkCancellation()
                try store.install(data)
            } catch is CancellationError { }
            catch { store.message = error.localizedDescription }
        }.alert("壁纸提示", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("好") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

}

// SPDX-License-Identifier: GPL-3.0-or-later
// Stable semantic identities, independent of view recreation and display names.
struct MistCardTarget: Identifiable {
    let id: String
    let title: String
    let group: String
    static let fixed: [MistCardTarget] = [
        .init(id: "create.preview", title: "屏幕预览外壳", group: "制卡"),
        .init(id: "create.transfer", title: "NFC 传输状态", group: "制卡"),
        .init(id: "library.import", title: "本地文件导入", group: "卡包"),
        .init(id: "library.empty", title: "空卡包提示", group: "卡包"),
        .init(id: "library.protection", title: "本地保护与备份", group: "卡包"),
        .init(id: "device.connection", title: "设备连接", group: "设备"),
        .init(id: "device.list", title: "设备列表容器", group: "设备"),
        .init(id: "device.version", title: "设备信息与版本", group: "设备"),
        .init(id: "device.diagnostics", title: "服务与安全边界", group: "设备"),
        .init(id: "settings.wallpaper", title: "壁纸设置", group: "设置"),
        .init(id: "settings.blur", title: "卡片模糊设置", group: "设置"),
        .init(id: "settings.about", title: "关于 Link-Card", group: "设置"),
        .init(id: "settings.reminders", title: "发送前提醒", group: "设置"),
        .init(id: "settings.diagnostics", title: "NFC 高级诊断", group: "设置"),
        .init(id: "settings.licenses", title: "协议来源与许可", group: "设置"),
        .init(id: "navigation.tabs", title: "底部导航外壳", group: "导航")
    ]
    static func library(_ id: UUID) -> String { "library.card." + id.uuidString.lowercased() }
}

enum MistBlurChannel { case controls, workbench }

final class MistBlurStore: ObservableObject {
    private let defaults: UserDefaults
    private static let controlsKey = "appearance.blur.controls.v2"
    private static let workbenchKey = "appearance.blur.workbench.v2"
    private static let migratedKey = "appearance.blur.migrated.v2"
    @Published private(set) var global: Double
    @Published private(set) var workbench: Double
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if !defaults.bool(forKey: Self.migratedKey) {
            let previous = Self.clamp((defaults.object(forKey: "appearance.cardBlur.global.v1") as? Double) ?? 70)
            let old = defaults.dictionary(forKey: "appearance.cardBlur.overrides.v1") ?? [:]
            let base = Self.clamp((old["workbench.base"] as? Double) ?? previous)
            defaults.set(previous, forKey: Self.controlsKey)
            defaults.set(base, forKey: Self.workbenchKey)
            defaults.set(true, forKey: Self.migratedKey)
            // Keep legacy keys and all user files, but never consult overrides again.
        }
        global = Self.readStrength(defaults, key: Self.controlsKey)
        workbench = Self.readStrength(defaults, key: Self.workbenchKey)
    }
    // UserDefaults argument domains and imported preferences can contain numeric
    // strings. Treat those exactly like stored numbers, not silently as 70.
    private static func readStrength(_ defaults: UserDefaults, key: String) -> Double {
        let object = defaults.object(forKey: key)
        if let number = object as? NSNumber { return clamp(number.doubleValue) }
        if let text = object as? String, let number = Double(text) { return clamp(number) }
        return 70
    }
    private static func clamp(_ value: Double) -> Double { value.isFinite ? min(100, max(0, value)) : 70 }
    func strength(for id: String) -> Double { global }
    func strength(channel: MistBlurChannel) -> Double { channel == .workbench ? workbench : global }
    func setGlobal(_ value: Double) {
        let next = Self.clamp(value)
        guard next != global else { return }
        global = next; defaults.set(next, forKey: Self.controlsKey)
    }
    func setWorkbench(_ value: Double) {
        let next = Self.clamp(value)
        guard next != workbench else { return }
        workbench = next; defaults.set(next, forKey: Self.workbenchKey)
    }
}

/// A stationary public UIKit material with a continuously adjustable visual tint.
/// 0 disables the material; 1...100 retain live system blur and vary the tint.
/// This is visual strength, NOT a calibrated or interpolated Gaussian radius.
/// Foreground text, avatars and pixel previews are siblings, never blurred content.
final class MistEffectView: UIVisualEffectView {
    private let visualTint = UIView()
    private var intensity: CGFloat = 0
    private var isRebuilding = false
    private(set) var rebuildCount = 0
    override init(effect: UIVisualEffect?) {
        super.init(effect: nil)
        isUserInteractionEnabled = false
        visualTint.isUserInteractionEnabled = false
        visualTint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.insertSubview(visualTint, at: 0)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshEffect), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setIntensity(_ value: Double) {
        let next = CGFloat((value.isFinite ? min(100, max(0, value)) : 70) / 100)
        if next == intensity, next == 0 || effect != nil { return }
        intensity = next
        if intensity == 0 { stopEffect(); return }
        rebuild()
    }
    private func clearEffect() {
        effect = nil
        visualTint.backgroundColor = .clear
    }
    func stopEffect() {
        intensity = 0
        clearEffect()
    }
    @objc private func refreshEffect() { if window != nil { rebuild() } }
    private func rebuild() {
        guard !isRebuilding else { return }
        isRebuilding = true
        defer { isRebuilding = false }
        guard window != nil, intensity > 0 else { clearEffect(); return }
        // No retained animation, sampling, snapshots, private filters, or alpha
        // on the effect/its ancestors. UIKit continues to blur live content.
        if effect == nil {
            effect = UIBlurEffect(style: .systemUltraThinMaterial)
            rebuildCount += 1
        }
        let color: UIColor = traitCollection.userInterfaceStyle == .dark ? .black : .white
        visualTint.backgroundColor = color.withAlphaComponent(0.42 * intensity)
        visualTint.frame = contentView.bounds
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            // Keep requested strength across temporary detach/reattach.
            clearEffect()
        } else { rebuild() }
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection == nil || traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) { rebuild() }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

private struct MistBackdrop: UIViewRepresentable {
    let strength: Double
    func makeUIView(context: Context) -> MistEffectView { MistEffectView(effect: nil) }
    func updateUIView(_ uiView: MistEffectView, context: Context) { uiView.setIntensity(strength) }
    static func dismantleUIView(_ uiView: MistEffectView, coordinator: ()) { uiView.stopEffect() }
}

private struct MistWorkbenchContentKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var mistWorkbenchContent: Bool {
        get { self[MistWorkbenchContentKey.self] }
        set { self[MistWorkbenchContentKey.self] = newValue }
    }
}

struct MistSurface: View {
    let id: String
    var radius: CGFloat = 18
    var channel: MistBlurChannel = .controls
    @Environment(\.mistWorkbenchContent) private var inWorkbench
    @EnvironmentObject private var blur: MistBlurStore
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            if !inWorkbench || id == "action" {
                MistBackdrop(strength: blur.strength(channel: channel))
            }
            // Fixed readability floor even with intensity zero and a busy photo.
            (scheme == .dark ? Color.black.opacity(0.70) : Color.white.opacity(0.82))
        }.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct MistBlurSettings: View {
    @EnvironmentObject private var blur: MistBlurStore
    @ObservedObject var library: LocalCardLibrary
    var body: some View {
        MistPanel(id: "settings.blur") {
            VStack(alignment: .leading, spacing: 18) {
                Label("背景模糊", systemImage: "slider.horizontal.3").font(.headline)
                Text("仅改变背景；文字、图标、头像和 200 × 200 卡片保持清晰。")
                    .font(.subheadline).foregroundStyle(MistStyle.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("控件背景 · \(Int(blur.global)) / 100")
                    Slider(value: Binding(get: { blur.global }, set: { blur.setGlobal($0) }), in: 0...100, step: 1)
                        .accessibilityLabel("控件背景模糊").accessibilityIdentifier("blur.controls")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("工作台背景 · \(Int(blur.workbench)) / 100")
                    Slider(value: Binding(get: { blur.workbench }, set: { blur.setWorkbench($0) }), in: 0...100, step: 1)
                        .accessibilityLabel("工作台背景模糊").accessibilityIdentifier("blur.workbench")
                }
                Text("控件和工作台的 0 关闭材质，1–100 调节系统实时模糊上的视觉雾感，并非高斯模糊半径。控件包含按钮、侧栏和连接面板；壁纸模糊仍在下方独立调整。设置仅保存在本机。")
                    .font(.footnote).foregroundStyle(MistStyle.secondary)
            }
        }
    }
}

struct MistActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 12).padding(.vertical, 8)
            .background { MistSurface(id: "action", radius: 14) }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MistStyle.accent.opacity(configuration.isPressed ? 0.5 : 0.12)))
    }
}

/// Production presentation state; stowing never resets the last working height or editor.
final class WorkbenchState: ObservableObject {
    // Non-published diagnostics: geometry/render probes must never invalidate the view tree.
    var frames: [String: CGRect] = [:]
    var renderCount = 0
    @Published var tab: MainTab = .create
    @Published var expanded = false
    var stowed: Bool { false } // Legacy requests resolve to compact, never an unreachable state.
    func toggle() { expanded.toggle() }
    func stow() { expanded = false }
    func restore() { }
    init(defaults: UserDefaults = .standard) {
        // Older builds did not persist stowed, but normalize imported preferences too.
        for key in ["workbench.stowed", "workbench.stowed.v1", "fusion.stowed.v1"] {
            if defaults.bool(forKey: key) { defaults.set(false, forKey: key) }
        }
    }
    static func previewSide(width: CGFloat) -> CGFloat { min(230, max(0, width * 0.68 - 20)) }
    static func availableHeight(proposed: CGFloat, top: CGFloat, bottomInset: CGFloat, tabTop: CGFloat?) -> CGFloat {
        let safeHeight = max(0, proposed - max(0, bottomInset))
        guard let tabTop = tabTop else { return safeHeight }
        return max(0, min(safeHeight, tabTop - top))
    }
    static func height(available: CGFloat, expanded: Bool, accessibility: Bool, keyboard: Bool) -> CGFloat {
        if keyboard { return max(0, available - 4) }
        if expanded || accessibility { return max(0, available * 0.78) }
        return min(300, max(0, available * 0.48))
    }
}

/// Lightweight production geometry seam; records actual safe-area/tab layout, not guessed constants.
struct WorkbenchFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}
extension View {
    func recordWorkbenchFrame(_ name: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: WorkbenchFrames.self,
                value: [name: proxy.frame(in: .global)])
        })
    }
}
