// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct FusionShell<Content: View>: View {
    @ObservedObject var state: FusionState
    @ObservedObject var workbench: WorkbenchState
    @ObservedObject var wallpaper: WallpaperStore
    @ObservedObject var library: LocalCardLibrary
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var cardBlur: MistBlurStore
    @StateObject private var person = FusionProfileStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let keyboard: Bool
    let busy: Bool
    let content: Content
    init(state: FusionState, workbench: WorkbenchState, wallpaper: WallpaperStore,
         library: LocalCardLibrary, keyboard: Bool, busy: Bool, @ViewBuilder content: () -> Content) {
        self.state = state; self.workbench = workbench; self.wallpaper = wallpaper
        self.library = library; self.keyboard = keyboard; self.busy = busy; self.content = content()
    }
    private var spring: Animation? { reduceMotion || scenePhase != .active ? nil : .interactiveSpring(response: 0.46, dampingFraction: 0.78, blendDuration: 0.12) }
    // GestureState also resets after recognizer cancellation; onEnded alone does not.
    @GestureState private var handleDrag: FusionWorkbenchDrag?
    @State private var handleSession = FusionWorkbenchDragSession()
    private var opened: Bool { workbench.expanded }
    private var targetProgress: CGFloat { opened ? 2 : 1 }
    var body: some View {
        GeometryReader { geo in
            let width = FusionState.drawerWidth(geo.size.width)
            let liveDrag = handleDrag.flatMap { sample in
                sample.matches(size: geo.size, keyboard: keyboard, accessibility: typeSize.isAccessibilitySize)
                    && scenePhase == .active ? sample : nil
            }
            let progress = liveDrag?.progress ?? targetProgress
            let layout = FusionWorkbenchGeometry(size: geo.size, progress: progress, keyboard: keyboard, accessibility: typeSize.isAccessibilitySize)
            ZStack(alignment: .topLeading) {
                // Only the wallpaper and the panel's background reach past safe areas.
                // Interactive content remains inside the system's usable rectangle.
                MistWallpaper(store: wallpaper).allowsHitTesting(false)
                if !keyboard {
                    toolbar(width: width, compact: geo.size.height < 600)
                        .frame(height: geo.size.height < 600 ? 64 : 92)
                        .padding(.horizontal, 20)
                }
                desk(layout: layout, bottomInset: geo.safeAreaInsets.bottom, size: geo.size)
                    .frame(width: layout.panel.width, height: layout.panel.height)
                    .position(x: layout.panel.midX, y: layout.panel.midY)
                if !keyboard {
                    Button { state.profile = true } label: {
                        FusionAvatar(image: person.image).frame(width: 56, height: 56)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("fusion.avatar")
                        .accessibilityLabel("个人资料，仅保存在本机")
                        .frame(width: 56, height: 56)
                        .background {
                            MistSurface(id: "fusion.avatar.support", radius: 37, channel: .controls)
                                .frame(width: 74, height: 74)
                                .mask(FusionAvatarSupport().fill(style: FillStyle(eoFill: true)))
                                .allowsHitTesting(false)
                        }
                        .recordWorkbenchFrame("avatar")
                        .position(x: layout.avatar.midX, y: layout.avatar.midY)
                }
                NativeFluidDrawer(state: state, active: scenePhase == .active, busy: busy,
                                  reduceMotion: reduceMotion, strength: cardBlur.strength(channel: .sidebar),
                                  menu: drawer()
                                    .environmentObject(cardBlur))
                    .frame(width: 0, height: 0).allowsHitTesting(false)
                    .transaction { $0.animation = nil }
            }
            // One animation owner for panel + avatar. Tracking is unanimated;
            // release (including returning to the same detent) settles once.
            .animation(liveDrag == nil ? spring : nil, value: progress)
        }
        .sheet(isPresented: $state.profile) { FusionProfileView(store: person) }
        .onChange(of: keyboard) { visible in
            if visible && !workbench.expanded { workbench.expanded = true }
        }
    }
    private func toolbar(width: CGFloat, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            FusionClock(compact: compact).frame(maxWidth: .infinity, alignment: .leading)
            FusionButton(title: "菜单", symbol: "line.3.horizontal", id: "fusion.menu") {
                state.drawerOwner?.request(open: !(state.drawerOwner?.targetOpen ?? false))
            }.frame(width: 44, height: 44)
                .background { MistSurface(id: "fusion.menu", radius: 22) }
        }.recordWorkbenchFrame("fusion.toolbar")
    }
    private func collapseOrExpand() {
        state.search = ""
        workbench.restore(); workbench.expanded = !opened
    }
    private func handleGesture(size: CGSize, travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("workbench.shell"))
            .updating($handleDrag) { drag, sample, transaction in
                // The handle moves during tracking. Its local coordinates must
                // never feed back into the geometry that moved the handle.
                transaction.animation = nil
                transaction.disablesAnimations = true
                guard scenePhase == .active else { return }
                let current = sample ?? FusionWorkbenchDrag(origin: targetProgress, travel: travel,
                    size: size, keyboard: keyboard, accessibility: typeSize.isAccessibilitySize,
                    translation: drag.translation)
                if sample == nil { handleSession.start = current }
                guard current.matches(size: size, keyboard: keyboard,
                                      accessibility: typeSize.isAccessibilitySize) else { return }
                let next = current.tracking(drag.translation)
                if sample != next { sample = next }
            }
            .onEnded { drag in
                defer { handleSession.start = nil }
                guard let sample = handleSession.start, sample.vertical, scenePhase == .active,
                      sample.matches(size: size, keyboard: keyboard,
                                     accessibility: typeSize.isAccessibilitySize) else { return }
                let expanded = sample.expanded(predictedTranslation: drag.predictedEndTranslation.height)
                if !state.search.isEmpty { state.search = "" }
                if workbench.expanded != expanded { workbench.expanded = expanded }
                // GestureState performs the only transient reset, also on cancel.
            }
    }
    private func desk(layout: FusionWorkbenchGeometry, bottomInset: CGFloat, size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                FusionButton(title: opened ? "收起工作台" : "展开工作台", symbol: "", id: "workbench.handle") { collapseOrExpand() }
                    .overlay(Capsule().fill(Color.white).frame(width: 36, height: 4)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1).allowsHitTesting(false))
                    .frame(width: layout.handle.width, height: layout.handle.height)
                    .recordWorkbenchFrame("handle")
                    .highPriorityGesture(handleGesture(size: size, travel: layout.travel))
            }.padding(.trailing, 12).frame(height: layout.handle.height)
            HStack {
                Text(workbench.tab == .settings ? "设置" : "工作台")
                    .font(.title2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                FusionButton(title: "设置", symbol: "gearshape", id: "fusion.settings") { navigate(.settings) }
                    .frame(width: 88, height: 44)
                    .background { MistSurface(id: "fusion.settings", radius: 20) }
            }.padding(.horizontal, 16).frame(height: layout.header.height).clipped()
                .allowsHitTesting(layout.header.height >= 40)
                .recordWorkbenchFrame("workbench.header")
            Group {
                if !state.search.isEmpty { searchResults }
                else { content }
            }.frame(maxWidth: .infinity).frame(height: layout.content.height)
                .clipped().contentShape(Rectangle())
                .environment(\.mistWorkbenchContent, true)
                .recordWorkbenchFrame("panel")
            tabs.frame(height: layout.tabs.height).clipped()
        }
        .background {
            MistSurface(id: "workbench.base", radius: 0, channel: .workbench)
                .padding(.bottom, -bottomInset)
                .mask {
                    // Even-odd subtraction removes the actual backdrop, not a painted ring.
                    Group {
                        if keyboard { Rectangle() }
                        else { FusionNotch().fill(style: FillStyle(eoFill: true)) }
                    }.clipped().padding(.bottom, -bottomInset)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workbench.panel")
        .accessibilityValue(opened ? "expanded" : "compact")
    }
    private var tabs: some View {
        HStack(spacing: 8) {
            tab(.create, "制卡", "square.and.pencil", Color(red: 0.54, green: 0.65, blue: 0.91))
            tab(.device, "设备", "antenna.radiowaves.left.and.right", Color(red: 0.60, green: 0.81, blue: 0.73))
            tab(.library, "卡包", "square.stack", Color(red: 0.91, green: 0.79, blue: 0.51))
        }.padding(.horizontal, 12).padding(.vertical, 12)
            .recordWorkbenchFrame("tabs")
    }
    private func tab(_ value: MainTab, _ title: String, _ icon: String, _ color: Color) -> some View {
        Button { navigate(value) } label: {
            let labelLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 6))
            labelLayout {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .recordWorkbenchFrame("tab.\(value.rawValue).icon")
                Text(title)
                    .font(.system(size: typeSize.isAccessibilitySize ? 24 : 15, weight: .semibold))
                    .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                    .recordWorkbenchFrame("tab.\(value.rawValue).title")
            }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity).frame(height: typeSize.isAccessibilitySize ? 92 : 48)
                .recordWorkbenchFrame("tab.\(value.rawValue).button")
                .background(color.opacity(workbench.tab == value ? 0.80 : 0.68), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color(red: 0.13, green: 0.19, blue: 0.27))
        }.buttonStyle(.plain).disabled(busy)
            .accessibilityIdentifier("tab.\(value.rawValue)")
            .accessibilityAddTraits(workbench.tab == value ? .isSelected : [])
    }
    private func navigate(_ tab: MainTab) {
        guard !busy else { return }
        workbench.tab = tab; workbench.restore(); workbench.expanded = true
        state.search = ""; state.drawerOwner?.request(open: false)
    }
    private var searchResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(library.cards.filter { $0.name.localizedCaseInsensitiveContains(state.search) }) { card in
                    Button { navigate(.library) } label: { Label(card.name, systemImage: "doc").frame(minHeight: 44) }
                }
                ForEach([MainTab.create, .device, .library, .settings], id: \.rawValue) { tab in
                    let title = tab == .create ? "制卡" : tab == .device ? "设备连接" : tab == .library ? "本地卡包" : "外观设置"
                    if title.localizedCaseInsensitiveContains(state.search) {
                        Button(title) { navigate(tab) }.frame(minHeight: 44)
                    }
                }
                if "个人资料".localizedCaseInsensitiveContains(state.search) {
                    Button("个人资料 · 仅本地") { state.profile = true }.frame(minHeight: 44)
                }
                Text("搜索本机卡包名称与功能入口；不访问网络。").font(.caption).foregroundStyle(MistStyle.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
        }.scrollDismissesKeyboard(.interactively)
    }
    private func drawer() -> some View {
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Button { state.profile = true } label: {
                        FusionAvatar(image: person.image).frame(width: 56, height: 56)
                    }.accessibilityLabel("个人资料")
                    Spacer()
                    FusionButton(title: "关闭菜单", symbol: "xmark", id: "fusion.close") {
                        state.drawerOwner?.request(open: false)
                    }.frame(width: 44, height: 44)
                }.padding(.bottom, 8)
                TextField("搜索本机卡包与功能", text: $state.search).textFieldStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("fusion.search").submitLabel(.search)
                    .onSubmit { workbench.expanded = true; state.drawerOwner?.request(open: false) }
                drawerItem("卡包", "square.stack", .library)
                drawerItem("制卡", "square.and.pencil", .create)
                drawerItem("设备", "antenna.radiowaves.left.and.right", .device)
                Button { navigate(.settings) } label: {
                    Label("外观与设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }.disabled(busy).padding(.top, 16)
            }.padding(.leading, 24).padding(.trailing, 36).padding(.vertical, 20)
        }
        .buttonStyle(.plain) // Sidebar-only exception; other app buttons keep their surfaces.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("fusion.drawer")
    }

    private func drawerItem(_ title: String, _ icon: String, _ tab: MainTab) -> some View {
        Button { navigate(tab) } label: {
            Label(title, systemImage: icon)
                .font(.title3.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle()) // The entire visible row is a touch target, not only label glyphs.
        }.buttonStyle(.plain).disabled(busy)
            .accessibilityIdentifier("drawer.\(tab.rawValue)")
    }
}
