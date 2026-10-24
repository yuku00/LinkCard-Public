// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Attach once to the persistent root, not individual tab bodies.
extension View {
    func bleDiscoveryHost(_ ble: PCRBluetooth) -> some View { modifier(BLEDiscoveryHost(ble: ble)) }
}
private struct BLEDiscoveryHost: ViewModifier {
    @ObservedObject var ble: PCRBluetooth
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .onAppear { ble.setForeground(scenePhase == .active) }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .active: ble.setForeground(true)
                case .background: ble.setForeground(false)
                case .inactive: break // Permission sheets and Control Center are transient.
                @unknown default: break
                }
            }
            // Only the actual presentation dismissal is a cancellation candidate.
            // Child disappearance (e.g. settings) must never interrupt a connection.
            .sheet(item: $ble.connectionPrompt, onDismiss: {
                ble.connectionPromptDidDisappear()
            }) { device in
                BLEConnectionConfirmation(ble: ble, device: device)
            }
    }
}
private struct BLEConnectionConfirmation: View {
    @ObservedObject var ble: PCRBluetooth
    let device: PCRBluetooth.Device
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var profileID = BLEProfile.builtin.id
    @State private var remember = false
    @State private var selectedID: UUID?
    @State private var settings = false
    @State private var attempted = false
    @State private var initialized = false
    private var candidates: [PCRBluetooth.Device] {
        let matches = ble.devices.filter { ble.isCandidate($0) || $0.id == device.id }
        return matches.contains(where: { $0.id == device.id }) ? matches : [device] + matches
    }
    private var selection: PCRBluetooth.Device? {
        candidates.first { $0.id == selectedID }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "wave.3.right")
                            .font(.title2).foregroundStyle(MistStyle.accent)
                            .frame(width: 36, height: 44).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selection?.label ?? "选择设备").font(.headline)
                            Text(attempted ? ble.status : "已发现 · 请核对自有设备")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if candidates.count > 1 {
                        Picker("设备", selection: $selectedID) {
                            Text("请选择设备").tag(nil as UUID?)
                            ForEach(candidates) { candidate in
                                Text(candidate.label + " · " + candidate.maskedID).tag(Optional(candidate.id))
                            }
                        }.frame(minHeight: 44)
                    }
                    Toggle("记住并自动连接", isOn: $remember).frame(minHeight: 44)
                    Button {
                        guard let selected = selection else { return }
                        attempted = true
                        ble.confirmConnection(selected, profileID: profileID, remember: remember)
                    } label: {
                        Text("连接").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(MistActionStyle()).tint(MistStyle.accent)
                        .disabled(selection == nil || ble.active)
                }
                Section {
                    DisclosureGroup("高级") {
                        Picker("设备配置", selection: $profileID) {
                            ForEach(ble.preferences.profiles) { Text($0.name).tag($0.id) }
                        }.frame(minHeight: 44)
                        Text("名称与服务不是认证。连接只发现服务和订阅通知，不自动发送业务命令。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("已信任设备按保存顺序连接；失败最多尝试 3 次。取消或手动断开会暂停自动连接。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("关闭发现弹窗不会撤销信任；未知设备仍需手动确认。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("不再显示发现弹窗") { ble.setDiscoveryPrompt(false) }
                            .frame(minHeight: 44)
                        Button("蓝牙与多设备设置") { settings = true }.frame(minHeight: 44)
                    }.frame(minHeight: 44)
                }
            }
            .navigationTitle("连接设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { ble.cancelConnectionPrompt() }.frame(minHeight: 44)
                }
            }
        }
        .buttonStyle(MistActionStyle())
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(380), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if candidates.count == 1 { selectedID = device.id }
            profileID = ble.suggestedProfile(for: device)
        }
        .onChange(of: selectedID) { _ in
            remember = false
            attempted = false
            if let selected = selection { profileID = ble.suggestedProfile(for: selected) }
        }
        .sheet(isPresented: $settings) { BLEPreferencesView(ble: ble) }
    }
}

struct BLEPreferencesView: View {
    @ObservedObject var ble: PCRBluetooth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var adding = false
    var body: some View {
        NavigationStack {
            Form {
                Section("前台发现") {
                    Toggle("进入 App / 设备流程自动扫描", isOn: Binding(get: { ble.preferences.autoScan }, set: ble.setAutomaticScanning))
                    Toggle("显示发现设备连接弹窗", isOn: Binding(get: { ble.preferences.showDiscoveryPrompt }, set: ble.setDiscoveryPrompt))
                    Text("关闭弹窗仅隐藏提示，不撤销已授权自动连接。未知设备仍须在设备列表点选确认，绝不按名称或 RSSI 自动连接。")
                    Text("只在前台扫描，每轮最多 12 秒。首次蓝牙权限请点击扫描授权；蓝牙关闭须你在系统设置开启。后台停止扫描、连接与重试。")
                    Button("恢复本次发现") { ble.resumeDiscovery() }
                    Button("停止本次自动连接", role: .destructive) { ble.disconnect() }
                }
                Section("已信任设备 · 从上到下优先") {
                    if ble.preferences.trusted.isEmpty { Text("暂无；连接时勾选记住后添加。") }
                    ForEach(ble.preferences.trusted) { trust in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("••••" + trust.id.uuidString.suffix(4))
                            Text(ble.preferences.profiles.first(where: { $0.id == trust.profileID })?.name ?? "配置已移除").font(.caption)
                            let layout = typeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                : AnyLayout(HStackLayout(spacing: 12))
                            layout {
                                Button("设为最高优先级") { ble.prioritize(trust.id) }
                                Button("忘记", role: .destructive) { ble.forget(trust.id) }
                            }.buttonStyle(MistActionStyle())
                        }
                    }
                    Text("扫描窗口结束后，从本轮发现的已信任设备按此顺序选择一台。连接中不抢连；失败仅原目标有限重试，不切换别的设备。取消/手动断开后须点扫描或恢复才再次尝试。")
                }
                Section("配置与内置适配器") {
                    ForEach(ble.preferences.profiles) { profile in
                        VStack(alignment: .leading) {
                            Text(profile.name)
                            Text(DeviceAdapters.adapter(profile.adapterID)?.title ?? "未实现").font(.caption)
                            if profile.id != BLEProfile.builtin.id {
                                Button("移除此配置及其信任绑定", role: .destructive) { ble.removeProfile(profile.id) }
                            }
                        }
                    }
                    Button("添加设备配置") { adding = true }
                    Text("配置仅含发现与 GATT 通道数据。无脚本下载、无自定义原始命令；协议只能选本 App 已实现且有证据的适配器或仅连接。自定义名称不会改变 NFCPRO / PCR 实际命令门禁。")
                }
            }.navigationTitle("蓝牙与设备适配")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .sheet(isPresented: $adding) { BLEProfileEditor(ble: ble) }
        }
        .buttonStyle(MistActionStyle())
    }
}
private struct BLEProfileEditor: View {
    @ObservedObject var ble: PCRBluetooth
    @Environment(\.dismiss) private var dismiss
    @State private var profile = BLEProfile(id: UUID(), name: "", namePrefix: "", serviceUUID: "", writeUUID: "", notifyUUID: "", adapterID: "connect-only")
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("显示与发现标识") {
                    TextField("配置名称（不是协议身份证明）", text: $profile.name)
                    TextField("广播名前缀，可选", text: $profile.namePrefix)
                    TextField("Service UUID，可选", text: $profile.serviceUUID)
                }
                Section("已实现的适配器") {
                    Picker("协议", selection: $profile.adapterID) {
                        ForEach(DeviceAdapters.registered, id: \.id) { adapter in Text(adapter.title).tag(adapter.id) }
                    }
                    TextField("Write UUID，可选", text: $profile.writeUUID)
                    TextField("Notify UUID，可选", text: $profile.notifyUUID)
                    Text("仅连接可留空写入/通知 UUID；如填写须成组且属性验证通过。PCR 文本仅允许证据中的通道，并额外校验实际广播型号。未知协议不能凭 UUID 推导。")
                }
                if let error = error { Text(error).foregroundStyle(.red) }
            }.textInputAutocapitalization(.never).autocorrectionDisabled()
                .navigationTitle("添加设备配置")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            profile.serviceUUID = profile.serviceUUID.uppercased()
                            profile.writeUUID = profile.writeUUID.uppercased()
                            profile.notifyUUID = profile.notifyUUID.uppercased()
                            error = ble.addProfile(profile)
                            if error == nil { dismiss() }
                        }
                    }
                }
        }
        .buttonStyle(MistActionStyle())
    }
}
