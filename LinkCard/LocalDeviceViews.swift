// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UniformTypeIdentifiers

struct PCRDeviceView: View {
    @ObservedObject var ble: PCRBluetooth
    @State private var confirmVersion = false
    @State private var showOthers = false
    @State private var copied = false
    @State private var blePreferences = false
    @State private var revealUID = false
    @State private var copiedUID = false
    private var candidates: [PCRBluetooth.Device] { ble.devices.filter { ble.isCandidate($0) } }
    private var others: [PCRBluetooth.Device] { ble.devices.filter { !ble.isCandidate($0) } }
    private var identifyBusyReason: String? {
        guard ble.busy && !ble.identifying else { return nil }
        return ble.readingDeviceInformation ? "正在读取设备信息，完成后可识别卡片。" : "设备正在处理另一项请求，完成或超时后可识别卡片。"
    }
    private var disabledReason: String? {
        if ble.identifying { return "正在识别卡片；请等待完成或取消本次识别。" }
        if ble.busy { return ble.readingDeviceInformation ? "正在读取设备信息…" : "正在等待版本响应，请等待完成；超时将自动断开。" }
        if !ble.connected { return "请先扫描并点选你自己的设备连接。" }
        if !ble.ready { return "等待服务发现与通知订阅；若仍未就绪，请展开高级诊断核对服务与特征。" }
        if !ble.canQuery { return "当前广播名不在已验证文本型号名单中。请复制名称与服务信息核对实物型号；仅有 FF00/FF01/FF02 不能证明协议，不发送版本命令。" }
        return nil
    }
    var body: some View {
        MistPage("设备", subtitle: "前台保持连接，按需读取。") {
            connectionCard
            if !ble.active {
                MistPanel(id: "device.list") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("优先候选").font(.headline)
                            Spacer()
                            Text("\(candidates.count) 台").font(.subheadline.monospacedDigit())
                        }
                        Text("选择自有设备；已信任设备可自动连接。")
                            .font(.footnote).foregroundStyle(MistStyle.secondary)
                        if candidates.isEmpty {
                            Label(ble.scanning ? "正在寻找候选设备…" : "还没有匹配的候选设备", systemImage: "dot.radiowaves.left.and.right")
                                .font(.subheadline).padding(.vertical, 8)
                        }
                        ForEach(candidates) { device in deviceRow(device) }
                        DisclosureGroup(isExpanded: $showOthers) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("有些真机不广播服务或名称，可在这里手动查找。请靠近实物核对，不凭信号强弱判断型号。")
                                    .font(.footnote).foregroundStyle(MistStyle.secondary)
                                if others.isEmpty { Text("暂无其他设备").font(.subheadline) }
                                ForEach(others) { device in deviceRow(device) }
                            }.padding(.top, 12)
                        } label: { Text("显示其他设备（\(others.count)）") }
                    }
                }
            }
            identificationCard
            MistPanel(id: "device.version") {
                VStack(alignment: .leading, spacing: 14) {
                    Label("设备信息与版本", systemImage: "info.circle").font(.headline)
                    standardDeviceInformation
                    if PCRRoute.allowsText(ble.selected?.name ?? "") {
                    Divider()
                    Text("文本协议版本查询").font(.subheadline.weight(.semibold))
                    Text(ble.result).font(.subheadline).textSelection(.enabled)
                    Button { confirmVersion = true } label: {
                        Label("读取一次版本", systemImage: "arrow.down.circle")
                            .frame(minHeight: 44)
                    }.buttonStyle(MistActionStyle()).tint(MistStyle.link).disabled(disabledReason != nil)
                    if let reason = disabledReason {
                        Label(reason, systemImage: "lock.shield").font(.footnote).foregroundStyle(MistStyle.secondary)
                    } else {
                        Text("读取成功后保持连接；超时会停止并断开。")
                            .font(.footnote).foregroundStyle(MistStyle.secondary)
                    }
                    }
                }
            }
            MistPanel(id: "device.diagnostics") {
                DisclosureGroup("高级 · 协议与服务") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(ble.modelExplanation)
                        Text("NFCPRO 的 180A 软件版本由蓝牙设备自报，不是 PN532 芯片版本；不适用 PCRPANDA? 文本查询。")
                        if let device = ble.selected {
                            Text("名称：" + device.label).textSelection(.enabled)
                            Text("广播线索：" + device.candidateReason)
                            if ble.writeLimit > 0 { Text("单次写入上限：\(ble.writeLimit) 字节") }
                            Button { copyDiagnostics(device) } label: {
                                Label(copied ? "已复制名称与服务" : "复制名称与服务属性", systemImage: "doc.on.doc")
                            }.frame(minHeight: 44)
                        }
                        if ble.services.isEmpty { Text("连接后显示服务；不自动读取特征值，不读取序列号。") }
                        ForEach(Array(ble.services.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        Text("复制内容仅含设备名称、服务 UUID 与特征属性；不含完整 identifier、序列号值或设备响应。")
                        Text("FF00 通道与 PCR 名称都不是认证。仅精确匹配的 NFCPRO 可由你点击启用基础寻卡；未知型号不试探、不写卡、不刷固件。仅 DFU 时停止。")
                    }.font(.footnote).foregroundStyle(MistStyle.secondary).padding(.top, 14)
                }
            }
        }
        .buttonStyle(MistActionStyle())
        .confirmationDialog("确认自有设备与型号", isPresented: $confirmVersion, titleVisibility: .visible) {
            Button("已取下卡片，读取一次版本") { ble.readVersion() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("请确认实物与显示的文本协议型号相符。名称可能被伪装；这不是认证。将只发 PCRPANDA?，不发空命令、不切换模式、不寻卡。")
        }
        .sheet(isPresented: $blePreferences) { BLEPreferencesView(ble: ble) }
        .bleModalActivity("device.settings", active: blePreferences)
        .bleModalActivity("device.version", active: confirmVersion)
        .onAppear { ble.enterDeviceFlow() }
        .onChange(of: ble.selected?.id) { _ in copied = false }
    }
    private var identificationCard: some View {
        MistPanel(id: "device.identification") {
            VStack(alignment: .leading, spacing: 12) {
                Label("基础寻卡", systemImage: "wave.3.right").font(.headline)
                Text("将启用易失性读卡模式，只识别 ISO 14443A。不读取保护扇区、不改 UID、不写卡、不破解或恢复密钥；不开云 API、不升级固件。")
                    .font(.footnote).foregroundStyle(MistStyle.secondary)
                Button {
                    revealUID = false
                    copiedUID = false
                    // Direct production action: no dialog, async dispatch or UI-only success state.
                    ble.identifyCard()
                } label: {
                    Label(ble.identifying ? "正在识别…" : "识别卡片", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }.disabled(ble.busy).accessibilityIdentifier("device.identify")
                HStack(alignment: .top, spacing: 8) {
                    if ble.identifying { ProgressView().accessibilityHidden(true) }
                    Text(ble.identifyMessage).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("device.identify.status")
                }
                if let reason = identifyBusyReason {
                    Text(reason).font(.footnote).foregroundStyle(MistStyle.secondary)
                        .accessibilityIdentifier("device.identify.disabledReason")
                }
                if ble.identifying {
                    Button("取消本次识别", role: .cancel) { ble.cancelIdentification() }
                        .frame(minHeight: 44).accessibilityIdentifier("device.identify.cancel")
                }
                if let card = ble.identifiedCard {
                    Text("UID · " + (revealUID ? card.uidHex : card.maskedUID)).font(.subheadline.monospaced())
                    HStack {
                        Button(revealUID ? "遮蔽 UID" : "显示 UID") { revealUID.toggle() }
                        Button(copiedUID ? "已复制 UID" : "复制 UID") {
                            UIPasteboard.general.setItems([["public.utf8-plain-text": card.uidHex]],
                                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
                            copiedUID = true
                        }
                    }.frame(minHeight: 44)
                    Text("ATQA 0x" + card.atqaHex + " · SAK 0x" + card.sakHex).font(.subheadline.monospaced())
                    Text(card.candidate).font(.subheadline)
                    Text("类型仅为候选，不能据 SAK 判断可克隆或可写 UID。UID 仅本地显示，复制由你主动触发。")
                        .font(.footnote).foregroundStyle(MistStyle.secondary)
                }
                Text("本版仅完成寻卡里程碑；读扇区、写卡留待后续。成功后保留连接；取消或异常会断开隔离。")
                    .font(.caption).foregroundStyle(MistStyle.secondary)
            }
        }
    }
    private var standardDeviceInformation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { ble.readDeviceInformation() } label: {
                Label(ble.readingDeviceInformation ? "正在读取…" : (ble.deviceInformation.isEmpty ? "读取设备信息" : "刷新设备信息"), systemImage: "arrow.clockwise")
                    .frame(minHeight: 44)
            }.buttonStyle(MistActionStyle()).tint(MistStyle.link)
                .disabled(!ble.canReadDeviceInformation || ble.busy)
                .accessibilityIdentifier("device.read")
            if !ble.deviceInformation.isEmpty {
                ForEach(PCRDeviceInformation.fields, id: \.uuid) { field in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(field.label).foregroundStyle(MistStyle.secondary)
                            Spacer(minLength: 12)
                            Text(ble.deviceInformation[field.uuid] ?? "尚未读取")
                                .font(field.uuid == "2A28" ? .headline : .subheadline)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label).foregroundStyle(MistStyle.secondary)
                            Text(ble.deviceInformation[field.uuid] ?? "尚未读取")
                        }
                    }.font(.subheadline).textSelection(.enabled)
                }
                Text("蓝牙设备自报 · 非 PN532 芯片版本")
                    .font(.caption).foregroundStyle(MistStyle.secondary)
            } else if !ble.connected {
                Text("连接后可读取型号、硬件、软件与厂商。")
                    .font(.footnote).foregroundStyle(MistStyle.secondary)
            } else if !ble.canReadDeviceInformation && !ble.busy {
                Text(ble.ready ? "设备未提供可读标准信息。" : "正在发现设备服务…")
                    .font(.footnote).foregroundStyle(MistStyle.secondary)
            }
        }
    }
    private var connectionCard: some View {
        MistPanel(id: "device.connection") {
            VStack(alignment: .leading, spacing: 12) {
                Label(ble.connected ? "蓝牙已连接" : (ble.active ? "正在连接" : "蓝牙未连接"), systemImage: ble.connected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .font(.headline).foregroundStyle(MistStyle.ink)
                if let device = ble.selected {
                    Text(device.label).font(.headline).textSelection(.enabled)
                        .accessibilityLabel("当前选择的设备名称：" + device.label)
                    Text("\(device.maskedID) · \(rssi(device))").font(.caption.monospacedDigit()).foregroundStyle(MistStyle.secondary)
                } else {
                    Text("连接你的 PCR 设备").font(.subheadline)
                }
                Text(ble.status).font(.subheadline).accessibilityAddTraits(.updatesFrequently)
                if let reason = ble.lastDisconnectReason, !ble.connected {
                    Label("上次断开：" + reason.rawValue, systemImage: "info.circle")
                        .font(.caption).foregroundStyle(MistStyle.secondary)
                }
                if ble.scanning || (ble.active && !ble.connected) { ProgressView() }
                if ble.active {
                    Button("取消并断开", role: .destructive) { ble.disconnect() }.frame(minHeight: 46)
                } else if ble.scanning {
                    Button("停止本次扫描") { ble.cancelConnectionPrompt() }.frame(minHeight: 46)
                } else {
                    Button { ble.scan() } label: {
                        Label("扫描附近设备", systemImage: "dot.radiowaves.left.and.right")
                            .frame(minHeight: 44)
                    }.buttonStyle(MistActionStyle()).tint(MistStyle.link)
                }
                Button("设备设置") { blePreferences = true }.frame(minHeight: 44)
                    .accessibilityIdentifier("device.settings")
                Text("前台跨页面保持连接，退到后台会停止。")
                    .font(.footnote).foregroundStyle(MistStyle.secondary)
            }
        }
    }
    private func rssi(_ device: PCRBluetooth.Device) -> String {
        device.rssi == 127 ? "信号不可用" : "RSSI \(device.rssi) dBm"
    }
    private func deviceRow(_ device: PCRBluetooth.Device) -> some View {
        Button { ble.requestConnection(device) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wave.3.right").font(.title3).padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(device.label).font(.headline).foregroundStyle(MistStyle.ink)
                    Text("\(device.maskedID) · \(rssi(device))").font(.caption.monospacedDigit())
                    Text(device.candidateReason + (device.isCandidate ? " · 候选，非认证" : " · 手动确认"))
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(MistStyle.secondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).padding(.top, 5)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(MistActionStyle()).accessibilityHint("连接并发现服务，不发送业务命令")
    }
    private func copyDiagnostics(_ device: PCRBluetooth.Device) {
        UIPasteboard.general.string = (["名称：" + device.label] + ble.services).joined(separator: "\n")
        copied = true
    }
}

private struct ExportedCard: Identifiable { let id = UUID(); let url: URL }
struct LocalCardLibraryView: View {
    @ObservedObject var library: LocalCardLibrary
    @State private var importing = false
    @State private var renameCard: LocalCard?
    @State private var newName = ""
    @State private var deleteCard: LocalCard?
    @State private var shareCard: LocalCard?
    @State private var exported: ExportedCard?
    @State private var exportURL: URL?
    var body: some View {
        MistPage("卡包", subtitle: "你的文件，安静留在本机。") {
            MistPanel(id: "library.import") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("本地文件", systemImage: "tray.full").font(.headline)
                        Spacer()
                        Text("\(library.cards.count) 份").font(.subheadline.monospacedDigit())
                    }
                    Text("只管理你主动导入的备份，不读取原云卡包，也不发送到 PCR。")
                        .font(.subheadline).foregroundStyle(MistStyle.secondary)
                    Button { importing = true } label: {
                        Label("从文件导入", systemImage: "square.and.arrow.down")
                            .frame(minHeight: 44)
                    }.buttonStyle(MistActionStyle()).tint(MistStyle.link)
                    Text("bin / dump / txt · 每份不超过 2 MiB · 原样保存")
                        .font(.caption).foregroundStyle(MistStyle.secondary)
                }
            }
            if library.cards.isEmpty {
                MistPanel(id: "library.empty") {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "doc.badge.plus").font(.largeTitle).foregroundStyle(MistStyle.accent)
                        Text("从第一份备份开始").font(.title3.bold())
                        Text("点击上方导入，在「文件」中选择已有备份。未知格式会如实标注，不填零、不推断缺失块。")
                            .font(.subheadline).foregroundStyle(MistStyle.secondary)
                    }.padding(.vertical, 6)
                }
            }
            ForEach(library.cards) { card in
                MistPanel(id: MistCardTarget.library(card.id)) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(card.name, systemImage: "doc.text").font(.headline)
                        Text("\(card.fileExtension.uppercased()) · \(card.size) 字节")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(MistStyle.secondary)
                        Text(card.format).font(.subheadline).foregroundStyle(MistStyle.secondary)
                        DisclosureGroup("文件详情与 SHA-256") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("导入于 " + card.imported.formatted(date: .abbreviated, time: .shortened))
                                Text(card.sha256).font(.caption.monospaced()).textSelection(.enabled)
                            }.font(.footnote).padding(.top, 8)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 18) { cardActions(card) }
                            VStack(alignment: .leading, spacing: 8) { cardActions(card) }
                        }.buttonStyle(MistActionStyle())
                    }
                }
            }
            MistPanel(id: "library.protection") {
                DisclosureGroup("本地保护与备份") {
                    Text("文件存于应用私有目录，启用 iOS 完整文件保护并排除系统备份。不上传、不记录卡内容；卸载应用会删除卡包，请自行保管必要备份。Keychain 密钥管理不在本阶段。")
                        .font(.footnote).foregroundStyle(MistStyle.secondary).padding(.top, 12)
                }
            }
        }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .plainText], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { library.importFile(url) }
                case .failure: library.message = "导入未完成；没有修改文件。"
                }
            }
            .alert("重命名", isPresented: Binding(get: { renameCard != nil }, set: { if !$0 { renameCard = nil } })) {
                TextField("文件显示名称", text: $newName)
                Button("保存") { if let card = renameCard { library.rename(card, to: newName) }; renameCard = nil }
                Button("取消", role: .cancel) { renameCard = nil }
            } message: { Text("只修改卡包中的名称，不改文件内容与哈希。") }
            .confirmationDialog("删除这份本地文件？", isPresented: Binding(get: { deleteCard != nil }, set: { if !$0 { deleteCard = nil } }), titleVisibility: .visible) {
                Button("删除", role: .destructive) { if let card = deleteCard { library.delete(card) }; deleteCard = nil }
                Button("取消", role: .cancel) { deleteCard = nil }
            } message: { Text("删除不可撤销；不会删除最初从「文件」导入的原件。") }
            .confirmationDialog("导出可能包含敏感卡片内容", isPresented: Binding(get: { shareCard != nil }, set: { if !$0 { shareCard = nil } }), titleVisibility: .visible) {
                Button("确认并打开系统分享") {
                    if let card = shareCard {
                        do { let url = try library.export(card); exportURL = url; exported = ExportedCard(url: url) }
                        catch { library.message = "导出失败或文件完整性检查未通过。" }
                    }
                    shareCard = nil
                }
                Button("取消", role: .cancel) { shareCard = nil }
            } message: { Text("接收应用可能上传或保留文件；请只分享给可信位置。导出的是原始内容，不做脱敏。") }
            .alert("卡包提示", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
                Button("好") { library.message = nil }
            } message: { Text(library.message ?? "") }
            .sheet(item: $exported, onDismiss: { LocalCardLibrary.removeExport(exportURL); exportURL = nil }) { item in
                CardShareSheet(url: item.url)
            }
            .bleModalActivity("library.modal", active: importing || renameCard != nil || deleteCard != nil || shareCard != nil || exported != nil || library.message != nil)
    }
    @ViewBuilder private func cardActions(_ card: LocalCard) -> some View {
        Button("改名") { newName = card.name; renameCard = card }.frame(minHeight: 44)
        Button("导出") { shareCard = card }.frame(minHeight: 44)
        Button("删除", role: .destructive) { deleteCard = card }.frame(minHeight: 44)
    }

}

private struct CardShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
