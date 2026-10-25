// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreBluetooth
import Combine

final class PCRBluetooth: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Device: Identifiable {
        let peripheral: CBPeripheral
        var name: String
        var rssi: Int
        var advertisedServices: [String]
        var id: UUID { peripheral.identifier }
        var maskedID: String { "••••" + id.uuidString.suffix(4) }
        var label: String {
            let raw = name.isEmpty ? (peripheral.name ?? "") : name
            let clean = String(String.UnicodeScalarView(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })).trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? "未广播名称的设备" : String(clean.prefix(100))
        }
        var matchedServices: [String] {
            advertisedServices.filter { ["FF00", "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"].contains($0) }
        }
        // Discovery hint only: never used by canQuery or command routing.
        var isCandidate: Bool { name.uppercased().hasPrefix("PCR") || !matchedServices.isEmpty }
        var candidateReason: String {
            let reason = [name.uppercased().hasPrefix("PCR") ? "PCR 名称前缀" : "", matchedServices.isEmpty ? "" : "服务 " + matchedServices.joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: " · ")
            return reason.isEmpty ? "未匹配广播线索" : reason
        }
    }
    enum DisconnectReason: String {
        case user = "用户断开"
        case background = "退到后台"
        case bluetooth = "蓝牙不可用"
        case service = "服务错误"
        case timeout = "操作超时"
        case remote = "设备掉线"
    }
    @Published private(set) var lastDisconnectReason: DisconnectReason?
    @Published private(set) var devices = [Device]()
    @Published private(set) var status = "点击扫描，查找附近的自有设备。"
    @Published private(set) var scanning = false
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var active = false
    @Published private(set) var ready = false
    @Published private(set) var canQuery = false
    @Published private(set) var canReadDeviceInformation = false
    @Published private(set) var readingDeviceInformation = false
    @Published private(set) var identifying = false
    @Published private(set) var identifiedCard: PN532Card?
    @Published private(set) var identifyMessage = "仅识别 ISO 14443A；尚未寻卡。"
    private var identifyStep: NFCProIdentify.Step?
    private var identifyExchange: PN532Exchange?
    private var identifyReply: [UInt8]?
    private var identifyGeneration = 0
    private var identifyWait: DispatchWorkItem?
    private var identifySettling = false
    private var identifyChannel = [String]()
    private var pendingCard: PN532Card?
    @Published private(set) var identifyPhase = "idle"
    @Published private(set) var identifyFailurePhase: String?
    /// Pure readiness explanation for UI; no I/O, identifiers or protocol bytes.
    var identifyUnavailableReason: String? {
        if busy { return identifying ? "正在识别，请等待本次结果或取消。" : "设备正忙，请等待当前操作完成后再识别。" }
        if closing { return "连接正在结束，请重新连接后识别。" }
        if !connected { return "请先连接已记住的设备或选择新设备。" }
        if !ready { return "连接尚未就绪，请等待服务发现和通知订阅完成。" }
        if connectionProfile != .builtin { return "当前为自定义连接配置；识别需要内置 PCR 配置。" }
        if !PCRRoute.isNFCPro(selected?.name ?? "") { return "当前型号未准入；仅支持精确匹配的 PCR-NFCPRO / TD5322A，不向其他型号试探。" }
        if identifyChannel != ["FF00", "FF02", "FF01"] { return "当前不是识别所需的 FF00 通道；不会切换协议试探。" }
        if let model = deviceInformation["2A24"], model != "TD5322A" { return "标准型号信息未确认 TD5322A；识别已停止，请检查设备型号。" }
        return nil
    }
    var canIdentify: Bool {
        identifyUnavailableReason == nil && NFCProIdentify.permits(
            name: selected?.name ?? "", builtinProfile: connectionProfile == .builtin,
            channel: identifyChannel, model: deviceInformation["2A24"])
    }
    var preferencesRestoreMessage: String? { preferences.restorationWarning }
    /// UUID-keyed, display-only values. Never persisted or logged.
    @Published private(set) var deviceInformation = [String: String]()
    var modelExplanation: String {
        if active && connectionProfile.adapterID == "connect-only" { return "当前配置为仅连接模式；可发现服务和订阅配置通知，不发送版本或其他业务命令。" }
        return PCRRoute.explanation(for: selected?.name ?? "")
    }
    private var informationCharacteristics = [CBCharacteristic]()
    private var informationQueue = [CBCharacteristic]()
    private var pendingInformation: CBCharacteristic?
    @Published private(set) var services = [String]()
    @Published private(set) var result = "尚未读取版本"
    @Published private(set) var selected: Device?
    @Published private(set) var writeLimit = 0
    private var discoveryPublishedAt: [UUID: TimeInterval] = [:]
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var tx: CBCharacteristic?
    private var rx: CBCharacteristic?
    private var pendingServices = 0
    private var deadline: DispatchWorkItem?
    private var scanRequested = false
    private var closing = false
    private var fragments = [Data]()
    private var awaitingWrite = false
    private var parser = PCRTextReply()
    private var writeType: CBCharacteristicWriteType = .withResponse
    @Published private(set) var preferences = BLEPreferences.load()
    @Published var connectionPrompt: Device?
    private var foreground = false
    private var sessionSuppressed = false
    private var previousCentralState: CBManagerState?
    private var resumeAfterClosing = false
    /// A manual cancel is scoped to this cycle, not the app lifetime.
    private func beginDiscoveryCycle() {
        sessionSuppressed = false; attempts = 0; automaticTarget = nil
        automaticAttempt = false; retryAfterDisconnect = false
        retryWork?.cancel(); retryWork = nil
        resumeAfterClosing = active && closing
    }
    private var automaticAttempt = false
    private var attempts = 0
    private var retryWork: DispatchWorkItem?
    private var connectionProfile = BLEProfile.builtin
    private var retryAfterDisconnect = false
    private var automaticTarget: UUID?
    private var promptDismissalIsProgrammatic = false
    private var promptPresentationInFlight = false
    private var deferredConnectionPrompt: Device?
    private var deferredPromptIsManual = false
    private var presentationBlockers = Set<String>()
    private var presentationReleaseWork: [String: DispatchWorkItem] = [:]

    /// Shared root arbitration, driven only by explicit modal state transitions.
    /// The small release grace covers UIKit dismissal animations (Photos/file pickers
    /// do not expose SwiftUI onDismiss). New requests cancel the pending release.
    func setPresentationBlocker(_ key: String, active: Bool) {
        presentationReleaseWork.removeValue(forKey: key)?.cancel()
        if active {
            presentationBlockers.insert(key)
            if let prompt = connectionPrompt {
                deferredConnectionPrompt = prompt
                promptDismissalIsProgrammatic = true
                connectionPrompt = nil // Deferral is not user cancellation.
            }
        } else if presentationBlockers.contains(key) {
            let work = DispatchWorkItem { [weak self] in self?.finishPresentationBlocker(key) }
            presentationReleaseWork[key] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }
    func finishPresentationBlocker(_ key: String) {
        presentationReleaseWork.removeValue(forKey: key)?.cancel()
        presentationBlockers.remove(key)
        flushDeferredConnectionPrompt()
    }
    private func queueConnectionPrompt(_ device: Device?, manual: Bool) {
        deferredConnectionPrompt = device; deferredPromptIsManual = manual
        flushDeferredConnectionPrompt()
    }
    private func flushDeferredConnectionPrompt() {
        guard presentationBlockers.isEmpty, !promptPresentationInFlight,
              foreground, central?.state == .poweredOn, !active, !scanning,
              let pending = deferredConnectionPrompt else { return }
        // Re-resolve current scan results and saved UUIDs at presentation time.
        guard let current = devices.first(where: { $0.id == pending.id }),
              !preferences.trusted.contains(where: { $0.id == current.id }),
              deferredPromptIsManual || (!sessionSuppressed && preferences.showDiscoveryPrompt && isCandidate(current)) else {
            deferredConnectionPrompt = nil; return
        }
        deferredConnectionPrompt = nil
        promptDismissalIsProgrammatic = false
        connectionPrompt = current
    }
    func connectionPromptDidAppear() { promptPresentationInFlight = true }
    private func dismissConnectionPrompt() {
        deferredConnectionPrompt = nil
        promptDismissalIsProgrammatic = true
        connectionPrompt = nil
    }
    func connectionPromptDidDisappear() {
        promptPresentationInFlight = false
        if !promptDismissalIsProgrammatic { cancelConnectionPrompt() }
        flushDeferredConnectionPrompt()
    }

    func setForeground(_ value: Bool) {
        guard foreground != value else { return }
        foreground = value
        if value {
            beginDiscoveryCycle()
            if let warning = preferences.restorationWarning { status = warning; return }
            if preferences.autoScan { scanAutomatically() }
        } else {
            retryWork?.cancel(); retryWork = nil; retryAfterDisconnect = false; dismissConnectionPrompt()
            if active || scanning || scanRequested {
                stopScan()
                disconnect("已退到后台，扫描与连接已停止。", reason: .background, suppressSession: false)
            }
        }
    }
    func enterDeviceFlow() {
        if foreground && preferences.autoScan && !sessionSuppressed && !active && !scanning { scanAutomatically() }
    }
    private func preferenceChangeAllowed() -> Bool {
        guard let warning = preferences.restorationWarning else { return true }
        status = warning; return false
    }
    func setAutomaticScanning(_ value: Bool) {
        guard preferenceChangeAllowed() else { return }
        preferences.autoScan = value; preferences.save()
        if value { resumeDiscovery() }
        else { stopScan(); retryWork?.cancel(); retryWork = nil; retryAfterDisconnect = false; dismissConnectionPrompt() }
    }
    func setDiscoveryPrompt(_ value: Bool) {
        guard preferenceChangeAllowed() else { return }
        preferences.showDiscoveryPrompt = value; preferences.save()
        if !value { dismissConnectionPrompt() }
    }
    func addProfile(_ profile: BLEProfile) -> String? {
        if let warning = preferences.restorationWarning { return warning }
        if let error = profile.validationError { return error }
        guard preferences.profiles.count < 33, !preferences.profiles.contains(where: { $0.id == profile.id }) else { return "配置已存在或达到 32 个自定义配置上限。" }
        preferences.profiles.append(profile); preferences.save(); return nil
    }
    func removeProfile(_ id: UUID) {
        guard preferenceChangeAllowed() else { return }
        guard id != BLEProfile.builtin.id else { return }
        preferences.profiles.removeAll { $0.id == id }
        preferences.trusted.removeAll { $0.profileID == id }; preferences.save()
        if connectionProfile.id == id && active { disconnect("使用中的配置已移除，连接停止。") }
    }
    func forget(_ id: UUID) {
        guard preferenceChangeAllowed() else { return }
        preferences.trusted.removeAll { $0.id == id }; preferences.save()
        if selected?.id == id && active { disconnect("已忘记设备并断开。") }
    }
    func prioritize(_ id: UUID) {
        guard preferenceChangeAllowed() else { return }
        guard let index = preferences.trusted.firstIndex(where: { $0.id == id }) else { return }
        let item = preferences.trusted.remove(at: index); preferences.trusted.insert(item, at: 0); preferences.save()
    }
    func isCandidate(_ device: Device) -> Bool {
        preferences.profiles.contains { $0.matches(name: device.name, services: device.advertisedServices) }
    }
    func suggestedProfile(for device: Device) -> UUID {
        preferences.trusted.first(where: { $0.id == device.id })?.profileID ??
        preferences.profiles.first(where: { $0.matches(name: device.name, services: device.advertisedServices) })?.id ?? BLEProfile.builtin.id
    }
    private func connectTrusted(_ device: Device) -> Bool {
        guard let trust = preferences.trusted.first(where: { $0.id == device.id }),
              let profile = preferences.profiles.first(where: { $0.id == trust.profileID }),
              profile.validationError == nil else { return false }
        confirmConnection(device, profileID: profile.id, remember: true)
        return true
    }
    func requestConnection(_ device: Device) {
        guard foreground, !active else { return }
        if connectTrusted(device) { return }
        stopScan(); retryWork?.cancel(); retryWork = nil
        sessionSuppressed = true; queueConnectionPrompt(device, manual: true)
    }
    func cancelConnectionPrompt() {
        dismissConnectionPrompt(); sessionSuppressed = true; retryWork?.cancel(); retryWork = nil; retryAfterDisconnect = false; stopScan()
        status = "已取消本次发现；已记住设备仍保留，下次进入前台或蓝牙重新开启时按设置恢复。"
    }
    func confirmConnection(_ device: Device, profileID: UUID, remember: Bool) {
        guard foreground, !active, central?.state == .poweredOn,
              let profile = preferences.profiles.first(where: { $0.id == profileID }), profile.validationError == nil else {
            status = "连接尚不可用；请检查系统蓝牙、当前连接状态和所选配置。"; return
        }
        guard !remember || preferenceChangeAllowed() else { return }
        guard !remember || preferences.trusted.count < 100 || preferences.trusted.contains(where: { $0.id == device.id }) else {
            status = "已达 100 个信任设备上限，请先忘记不再使用的设备。"; return
        }
        dismissConnectionPrompt(); sessionSuppressed = false; automaticAttempt = false; retryWork?.cancel(); retryWork = nil
        if remember {
            let binding = BLETrust(id: device.id, profileID: profile.id)
            if let index = preferences.trusted.firstIndex(where: { $0.id == device.id }) { preferences.trusted[index] = binding }
            else { preferences.trusted.append(binding) }
            preferences.save()
        } else if preferences.restorationWarning == nil {
            // Explicitly turning Remember off revokes this UUID, unlike dismissing a sheet.
            preferences.trusted.removeAll { $0.id == device.id }; preferences.save()
        }
        automaticAttempt = preferences.autoScan && preferences.trusted.contains { $0.id == device.id && $0.profileID == profile.id }
        if automaticAttempt { attempts = 1; automaticTarget = device.id }
        connectionProfile = profile; connect(device)
    }
    func resumeDiscovery() { sessionSuppressed = false; attempts = 0; scan() }
    private func scanAutomatically() {
        guard foreground, preferences.autoScan, !sessionSuppressed, attempts < 3, !active, !scanning, retryWork == nil else { return }
        // Never trigger the initial system permission dialog merely by opening the App.
        guard CBCentralManager.authorization == .allowedAlways else {
            status = "自动发现需要蓝牙授权；首次请点击扫描并允许系统权限。"; return
        }
        startScanRequest()
    }
    // Internal completion seam is exercised by the host coordinator tests; not a timer bypass in UI.
    func finishDiscovery() {
        stopScan()
        guard foreground, !sessionSuppressed, !active else { return }
        // Wait for the complete scan window, then use explicit saved order, not arrival/RSSI.
        if preferences.autoScan, attempts < 3,
           let trust = preferences.trusted.first(where: { saved in
               (automaticTarget == nil || automaticTarget == saved.id) && devices.contains { $0.id == saved.id }
           }),
           let device = devices.first(where: { $0.id == trust.id }),
           let profile = preferences.profiles.first(where: { $0.id == trust.profileID }), profile.validationError == nil {
            dismissConnectionPrompt(); connectionProfile = profile; automaticAttempt = true; attempts += 1
            automaticTarget = trust.id
            connect(device); return
        }
        // Exhausted retries or autoScan off must not re-confirm an already saved UUID.
        if preferences.trusted.contains(where: { saved in devices.contains { $0.id == saved.id } }) {
            status = preferences.autoScan ? "已记住设备本轮连接已停止；点击扫描可重试。" : "发现已记住设备；自动连接已关闭，可手动连接。"
            return
        }
        if preferences.showDiscoveryPrompt {
            queueConnectionPrompt(devices.first(where: { device in
                isCandidate(device) && !preferences.trusted.contains { $0.id == device.id }
            }), manual: false)
        }
    }
    private func scheduleRetry() {
        guard automaticAttempt, attempts < 3, foreground, preferences.autoScan, !sessionSuppressed,
              central?.state == .poweredOn else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.retryWork = nil; self.scanAutomatically()
        }
        retryWork?.cancel(); retryWork = work
        status = "连接失败；仅在前台有限退避重试（最多 3 次连接），可取消。"
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempts * 2), execute: work)
    }
    func scan() {
        guard foreground, !active else { return }
        sessionSuppressed = false; attempts = 0; automaticTarget = nil; retryWork?.cancel(); retryWork = nil; dismissConnectionPrompt()
        startScanRequest()
    }
    private func startScanRequest() {
        guard foreground, !active else { return }
        devices = [] // Clear stale results even while waiting for permission/power.
        scanRequested = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else { beginScan() }
    }
    private func beginScan() {
        guard foreground, let central = central, central.state == .poweredOn, scanRequested else {
            if central?.state == .poweredOff { status = "系统蓝牙已关闭，请自行在系统设置中开启；App 无权替你开启。" }
            return
        }
        devices = []; scanning = true; status = "正在前台扫描 · 12 秒后选择候选或按信任优先级连接"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        arm(12) { [weak self] in self?.finishDiscovery() }
    }
    func stopScan() {
        let wasScanning = scanning
        scanRequested = false; central?.stopScan(); scanning = false
        if wasScanning { deadline?.cancel() }
        if !active { status = devices.isEmpty ? "未发现设备。请确认供电，并退出占用蓝牙的原小程序。" : "请选择你的设备；名称不是身份认证。" }
    }
    private func connect(_ device: Device) {
        guard foreground, !active, central?.state == .poweredOn else { return }
        stopScan(); selected = device; peripheral = device.peripheral
        peripheral?.delegate = self; closing = false; active = true
        deviceInformation = [:]; informationCharacteristics = []; informationQueue = []
        pendingInformation = nil; canReadDeviceInformation = false; readingDeviceInformation = false
        result = "尚未读取版本"; services = []; status = "正在连接…"
        central?.connect(device.peripheral, options: nil)
        arm(15) { [weak self] in self?.connectionFailed("连接或服务发现超时，已停止。") }
    }
    private func connectionFailed(_ message: String) {
        retryAfterDisconnect = automaticAttempt && foreground && !sessionSuppressed
        disconnect(message, reason: .timeout, suppressSession: false)
    }
    func disconnect(_ message: String = "已手动断开；本轮不再自动重连。", reason: DisconnectReason = .user, suppressSession: Bool = true) {
        if suppressSession { sessionSuppressed = true; retryAfterDisconnect = false }
        resumeAfterClosing = false
        retryWork?.cancel(); retryWork = nil; dismissConnectionPrompt()
        deadline?.cancel(); scanRequested = false; scanning = false; central?.stopScan()
        if identifying {
            identifyFailurePhase = identifyPhase
            if identifyMessage.hasPrefix("正在") || identifyMessage.hasPrefix("本次") {
                identifyMessage = "识别已停止：" + message + " 迟到响应不会用于下一次。"
            }
            identifyPhase = reason == .user || reason == .background ? "cancelled" : "failed"
        }
        identifying = false; identifyGeneration += 1; identifyWait?.cancel(); identifyWait = nil
        identifyStep = nil; identifyExchange = nil; identifyReply = nil; pendingCard = nil
        identifiedCard = nil; identifySettling = false; identifyChannel = []
        busy = false; ready = false; canQuery = false; connected = false
        canReadDeviceInformation = false; readingDeviceInformation = false
        informationQueue = []; pendingInformation = nil; informationCharacteristics = []
        fragments = []; awaitingWrite = false; parser = PCRTextReply(); tx = nil; rx = nil
        lastDisconnectReason = reason
        status = message; closing = true
        if let peripheral = peripheral { central?.cancelPeripheralConnection(peripheral) }
        else { active = false }
    }
    /// User action only: four standard GATT reads, no business writes or protocol probes.
    func readDeviceInformation() {
        guard connected, canReadDeviceInformation, !busy, !closing else { return }
        busy = true; readingDeviceInformation = true; canReadDeviceInformation = false
        deviceInformation = Dictionary(uniqueKeysWithValues: PCRDeviceInformation.fields.map {
            ($0.uuid, "未提供可读特征")
        })
        informationQueue = informationCharacteristics
        for characteristic in informationQueue {
            deviceInformation[characteristic.uuid.uuidString] = "尚未读取"
        }
        readNextInformation()
    }
    private func readNextInformation() {
        guard readingDeviceInformation, !closing, let peripheral = peripheral else { return }
        guard !informationQueue.isEmpty else {
            finishQuery("设备信息已更新 · 保持连接")
            return
        }
        let characteristic = informationQueue.removeFirst()
        pendingInformation = characteristic
        deviceInformation[characteristic.uuid.uuidString] = "正在读取…"
        status = "正在读取标准设备信息；不发送业务命令。"
        arm(4) { [weak self] in
            guard let self = self else { return }
            if let pending = self.pendingInformation {
                self.deviceInformation[pending.uuid.uuidString] = "读取超时"
            }
            self.disconnect("标准设备信息读取超时，已断开；不重试、不切换协议。", reason: .timeout)
        }
        peripheral.readValue(for: characteristic)
    }
    /// Successful transactions clear only request state; GATT subscriptions stay alive.
    /// Timeouts still close the link, so late replies cannot leak into the next query.
    func finishQuery(_ message: String) {
        deadline?.cancel(); deadline = nil
        busy = false; readingDeviceInformation = false
        informationQueue = []; pendingInformation = nil
        fragments = []; awaitingWrite = false; parser = PCRTextReply()
        canReadDeviceInformation = connected && !closing && !informationCharacteristics.isEmpty
        status = message
    }
    func readVersion() {
        guard ready, canQuery, !busy, !closing, let peripheral = peripheral, let tx = tx else { return }
        // The only business write in this release. No flush, fallback or retry.
        let command = Data("PCRPANDA?\r\n".utf8)
        writeLimit = peripheral.maximumWriteValueLength(for: writeType)
        guard writeLimit > 0 else { disconnect("设备未提供有效写入上限。", reason: .service); return }
        parser = PCRTextReply(); busy = true; result = "正在等待版本响应…"
        fragments = stride(from: 0, to: command.count, by: writeLimit).map {
            command.subdata(in: $0..<min($0 + writeLimit, command.count))
        }
        arm(4) { [weak self] in self?.disconnect("版本查询超时，已断开；不重试、不切换协议。", reason: .timeout) }
        if tx.properties.contains(.write) { writeType = .withResponse }
        drain()
    }
    /// Explicit click only; never called by discovery, trust, version or connection callbacks.
    func identifyCard() {
        guard !busy else {
            if !identifying { identifyPhase = "blocked" }
            identifyMessage = identifyUnavailableReason ?? "设备正忙，请稍后再试。"
            status = identifyMessage
            return
        }
        guard canIdentify else {
            identifyPhase = "blocked"
            identifyMessage = identifyUnavailableReason ?? "当前设备未通过识别准入检查；不发送命令。"
            status = identifyMessage
            return
        }
        identifying = true; busy = true; identifiedCard = nil; pendingCard = nil
        identifyPhase = "starting"; identifyFailurePhase = nil
        identifyMessage = "正在启动识别：唤醒读卡通道…"
        status = identifyMessage
        identifyGeneration += 1; identifyStep = nil; identifyExchange = nil
        identifyReply = nil; identifySettling = false
        // Wake only, no embedded unvalidated vendor frame. After a quiet interval,
        // host ACK aborts any old command still pending across a BLE reconnection.
        sendIdentifyBytes(NFCProIdentify.wake)
    }
    func cancelIdentification() {
        guard identifying else { return }
        identifyMessage = "已取消本次寻卡；已断开以隔离迟到响应。重新连接后可再试。"
        disconnect("本次寻卡已取消，连接已隔离。")
    }
    private func sendIdentifyBytes(_ data: Data) {
        guard identifying, let peripheral = peripheral else { return }
        // 20-byte conservative BLE payload, also bounded by CoreBluetooth's actual limit.
        let limit = min(20, peripheral.maximumWriteValueLength(for: writeType))
        guard limit > 0 else { disconnect("设备未提供有效写入上限。", reason: .service); return }
        fragments = stride(from: 0, to: data.count, by: limit).map {
            data.subdata(in: $0..<min($0 + limit, data.count))
        }
        arm(identifyStep?.timeout ?? 2) { [weak self] in
            guard let self = self, self.identifying else { return }
            self.identifyMessage = self.identifyStep == .poll
                ? "寻卡等待超时，未取得有效结果；不能据此判定无卡。已断开，请重新连接。"
                : "读卡模式初始化或收尾超时；已停止并断开，不自动重试。"
            self.disconnect("寻卡事务超时，连接已隔离。", reason: .timeout)
        }
        drain()
    }
    private func sendIdentifyStep() {
        guard let step = identifyStep, identifying else { return }
        identifyExchange = PN532Exchange(command: step.command); identifyReply = nil
        switch step {
        case .sam: identifyPhase = "configuring"; identifyMessage = "正在配置易失性读卡模式…"
        case .retries: identifyPhase = "limiting"; identifyMessage = "正在设置有限寻卡次数…"
        case .poll: identifyPhase = "polling"; identifyMessage = "正在识别卡片…请将一张自有卡放在天线中心。"
        case .fieldOff: identifyPhase = "finishing"; identifyMessage = "正在关闭射频并确认本次结果…"
        }
        status = identifyMessage
        sendIdentifyBytes(step.packet)
    }
    private func identifyWritesDrained() {
        guard identifying, !awaitingWrite, fragments.isEmpty else { return }
        if identifyStep != nil { consumeIdentifyReply(); return }
        guard !identifySettling else { return }
        identifySettling = true
        let generation = identifyGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.identifying, self.identifyGeneration == generation else { return }
            self.identifyWait = nil
            if self.identifyExchange == nil {
                // Marker differentiates wake wait from abort wait; no response is parsed here.
                self.identifyExchange = PN532Exchange(command: 0)
                self.identifyPhase = "synchronizing"
                self.identifyMessage = "正在同步读卡通道，隔离旧响应…"
                self.status = self.identifyMessage
                self.identifySettling = false
                self.sendIdentifyBytes(NFCProIdentify.ack)
            } else {
                self.identifyStep = .sam; self.sendIdentifyStep()
            }
        }
        identifyWait = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    private func receiveIdentify(_ value: Data) {
        // Quarantine startup/abort notifications; no live command exists in this interval.
        guard identifyStep != nil, identifyExchange != nil else { return }
        do {
            if let reply = try identifyExchange?.feed(value) {
                identifyReply = reply; consumeIdentifyReply()
            }
        } catch { failIdentification() }
    }
    private func consumeIdentifyReply() {
        guard !awaitingWrite, fragments.isEmpty, let reply = identifyReply,
              let step = identifyStep, identifying else { return }
        identifyReply = nil
        do {
            if step == .poll { pendingCard = try PN532Card.parse(reply) }
            else if !reply.isEmpty { throw PN532Error.unexpected }
            switch step {
            case .sam: identifyStep = .retries
            case .retries: identifyStep = .poll
            case .poll: identifyStep = .fieldOff
            case .fieldOff:
                identifiedCard = pendingCard; pendingCard = nil
                identifyMessage = identifiedCard == nil ? "未发现 ISO 14443A 卡片；可调整位置后再点一次。" : "识别完成 · 射频已关闭 · 保持蓝牙连接"
                identifyPhase = "completed"
                identifying = false; identifyStep = nil; identifyExchange = nil
                finishQuery("本次寻卡完成 · 保持连接")
                return
            }
            sendIdentifyStep()
        } catch { failIdentification() }
    }
    private func failIdentification() {
        identifyMessage = "响应校验失败或设备拒绝命令；本次已停止并断开，不切换协议、不自动重发。"
        disconnect("寻卡响应异常，连接已隔离。", reason: .service)
    }
    private func drain() {
        guard busy, !closing, let peripheral = peripheral, let tx = tx else { return }
        if writeType == .withResponse {
            guard !awaitingWrite else { return }
            if !fragments.isEmpty {
                awaitingWrite = true
                peripheral.writeValue(fragments.removeFirst(), for: tx, type: .withResponse)
            }
        } else {
            while peripheral.canSendWriteWithoutResponse && !fragments.isEmpty {
                peripheral.writeValue(fragments.removeFirst(), for: tx, type: .withoutResponse)
            }
        }
        identifyWritesDrained()
    }
    private func arm(_ seconds: Double, _ action: @escaping () -> Void) {
        deadline?.cancel(); let work = DispatchWorkItem(block: action); deadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let previousState = previousCentralState
        previousCentralState = central.state
        if central.state == .poweredOn {
            if previousState != .poweredOn { beginDiscoveryCycle() }
            if scanRequested { beginScan() } else { scanAutomatically() }
            return
        }
        retryAfterDisconnect = false
        let message: String
        switch central.state {
        case .unauthorized: message = "蓝牙权限未允许。请在系统设置 → 隐私与安全性 → 蓝牙中允许 Link-Card。"
        case .poweredOff: message = "蓝牙已关闭，扫描及连接停止。请自行在系统设置中开启；App 无权开启系统蓝牙。"
        case .unsupported: message = "此设备不支持蓝牙低功耗连接。"
        default: message = "蓝牙暂不可用，扫描及连接停止。"
        }
        disconnect(message, reason: .bluetooth, suppressSession: false)
        peripheral = nil; active = false
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning else { return }
        let previous = devices.first(where: { $0.id == peripheral.identifier })
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName.flatMap { $0.isEmpty ? nil : $0 } ?? previous?.name ?? ""
        let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []) + (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        let services = Array(Set((previous?.advertisedServices ?? []) + uuids.map { $0.uuidString })).sorted()
        let item = Device(peripheral: peripheral, name: name, rssi: RSSI.intValue, advertisedServices: services)
        let now = ProcessInfo.processInfo.systemUptime
        if let i = devices.firstIndex(where: { $0.id == item.id }) {
            let old = devices[i]
            // Names/services are discovery semantics: publish immediately. RSSI is display-only.
            let metadataChanged = old.name != item.name || old.advertisedServices != item.advertisedServices
            guard metadataChanged || (old.rssi != item.rssi && now - (discoveryPublishedAt[item.id] ?? 0) >= 0.3) else { return }
            devices[i] = item
            discoveryPublishedAt[item.id] = now
        } else if devices.count < 100 {
            devices.append(item)
            discoveryPublishedAt[item.id] = now
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard foreground, self.peripheral === peripheral, !closing else { central.cancelPeripheralConnection(peripheral); return }
        connected = true; status = "已连接，正在发现服务（不发送业务命令）…"
        peripheral.discoverServices(nil)
    }
    private func resumeDiscoveryAfterClosing() {
        guard resumeAfterClosing else { return }
        resumeAfterClosing = false
        scanAutomatically()
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        let retry = !closing && automaticAttempt
        if !closing { disconnect("连接失败，请检查设备供电或占用情况。", reason: .service, suppressSession: false) }
        self.peripheral = nil; active = false
        if retry || retryAfterDisconnect { retryAfterDisconnect = false; scheduleRetry() }
        resumeDiscoveryAfterClosing()
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        let retry = (!closing && automaticAttempt && !busy) || retryAfterDisconnect
        if !closing { disconnect("设备掉线；当前请求已取消。", reason: .remote, suppressSession: busy) }
        self.peripheral = nil; active = false; retryAfterDisconnect = false
        if retry { scheduleRetry() }
        resumeDiscoveryAfterClosing()
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral, !closing else { return }
        guard error == nil, let found = peripheral.services, !found.isEmpty else { disconnect("无法发现服务。", reason: .service); return }
        pendingServices = found.count
        for service in found { peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard self.peripheral === peripheral, !closing else { return }
        guard error == nil else { disconnect("特征发现失败，已停止。", reason: .service); return }
        services.append("服务 " + service.uuid.uuidString)
        for c in service.characteristics ?? [] {
            let p = c.properties
            services.append("  \(c.uuid.uuidString) · \(p.contains(.write) ? "写 " : "")\(p.contains(.writeWithoutResponse) ? "无响应写 " : "")\(p.contains(.notify) ? "通知 " : "")\(p.contains(.indicate) ? "指示 " : "")\(p.contains(.read) ? "读" : "")")
        }
        pendingServices -= 1
        guard pendingServices == 0 else { return }
        if let informationService = peripheral.services?.first(where: { $0.uuid == CBUUID(string: "180A") }) {
            informationCharacteristics = PCRDeviceInformation.fields.compactMap { field in
                informationService.characteristics?.first(where: {
                    $0.uuid == CBUUID(string: field.uuid) && $0.properties.contains(.read)
                })
            }
        }
        for map in connectionProfile.channels {
            guard let s = peripheral.services?.first(where: { $0.uuid == CBUUID(string: map[0]) }),
                  let write = s.characteristics?.first(where: { $0.uuid == CBUUID(string: map[1]) }),
                  let notify = s.characteristics?.first(where: { $0.uuid == CBUUID(string: map[2]) }),
                  write !== notify,
                  write.properties.contains(.write) || write.properties.contains(.writeWithoutResponse),
                  notify.properties.contains(.notify) || notify.properties.contains(.indicate) else { continue }
            tx = write; rx = notify
            identifyChannel = [s.uuid.uuidString, write.uuid.uuidString, notify.uuid.uuidString]
            writeType = write.properties.contains(.write) ? .withResponse : .withoutResponse
            writeLimit = peripheral.maximumWriteValueLength(for: writeType)
            peripheral.setNotifyValue(true, for: notify)
            status = "正在订阅匹配通知；未发送业务命令。"
            return
        }
        deadline?.cancel()
        if peripheral.services?.contains(where: { $0.uuid == CBUUID(string: "FE59") }) == true {
            disconnect("仅发现 DFU／未匹配业务通道：已停止并断开，不退出 DFU、不刷固件。", reason: .service)
        } else {
            canReadDeviceInformation = !informationCharacteristics.isEmpty
            status = canReadDeviceInformation ? "已连接 · 可读取设备信息" : "已连接 · 未提供可读设备信息"
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, characteristic === rx, !closing else { return }
        guard error == nil, characteristic.isNotifying else { disconnect("通知订阅失败，已停止。", reason: .service); return }
        deadline?.cancel(); ready = true
        canQuery = PCRRoute.allowsText(selected?.name ?? "")
            && DeviceAdapters.adapter(connectionProfile.adapterID)?.permitsVersion(advertisedName: selected?.name ?? "") == true
        canReadDeviceInformation = !informationCharacteristics.isEmpty
        status = canQuery ? "已连接 · 可读取版本" : "已连接 · 可读取设备信息"
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, characteristic === tx, busy, !closing else { return }
        guard error == nil else { disconnect("写入失败，已停止；不自动重试。", reason: .service); return }
        awaitingWrite = false; drain()
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }; drain()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral, !closing else { return }
        if readingDeviceInformation {
            // Ignore all unsolicited notifications and non-current read callbacks.
            guard busy, characteristic === pendingInformation else { return }
            deadline?.cancel()
            deviceInformation[characteristic.uuid.uuidString] = error == nil
                ? PCRDeviceInformation.displayValue(characteristic.value)
                : "读取失败（未重试）"
            pendingInformation = nil
            readNextInformation()
            return
        }
        guard self.peripheral === peripheral, characteristic === rx, busy, !closing else { return }
        guard error == nil, let value = characteristic.value else { disconnect("通知接收失败。", reason: .service); return }
        if identifying { receiveIdentify(value); return }
        do {
            if let version = try parser.feed(value) {
                result = version
                finishQuery("版本已更新 · 保持连接")
            }
        } catch { disconnect("版本响应格式或状态异常，已断开；不切换协议。", reason: .service); result = "未取得有效版本" }
    }
}
