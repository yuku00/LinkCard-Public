// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreNFC
import Combine

struct CardIdentity: Equatable {
    let uid: Data
    let summary: String
    let knownModel: Bool
    let mailboxReady: Bool
}

/// All mutable NFC state and every command run on one serial queue.
/// Main-thread published properties are presentation only, never protocol state.
final class NFCService: NSObject, ObservableObject, NFCTagReaderSessionDelegate {
    @Published private(set) var busy = false
    @Published private(set) var progress = 0
    @Published private(set) var status = "准备好内容，即可发送到设备"
    @Published private(set) var identity: CardIdentity?
    @Published private(set) var logs = [String]()
    private let queue = DispatchQueue(label: "LinkCard.NFC.serial")
    private var session: NFCTagReaderSession?
    private var tag: NFCISO15693Tag?
    private var running = false
    private var detected = false
    private var generation = UUID()
    private var pending: UUID?
    private var packets = [Data]()
    private var approvedUID: Data?
    private var packetIndex = 0
    private var wrote = false
    private var timeout: DispatchWorkItem?
    private var wholeTimeout: DispatchWorkItem?
    private let addressed: NFCISO15693RequestFlag = [.highDataRate, .address]

    func identify() { begin(frame: nil) }
    /// Explicit user intent; identification and all preflight checks share this session.
    func send(frame: Data) { begin(frame: frame) }
    func cancel() { queue.async { self.finish("已取消。若开始过传输，请板卡断电后普通模式重启。", error: true) } }

    private func publish(_ action: @escaping () -> Void) { DispatchQueue.main.async(execute: action) }
    private func log(_ text: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        publish {
            self.logs.append("\(stamp)  \(text)")
            if self.logs.count > 250 { self.logs.removeFirst(self.logs.count-250) }
        }
    }
    private func errorDetails(_ error: Error, depth: Int = 0) -> String {
        let ns = error as NSError
        var text = "domain=\(ns.domain) code=\(ns.code) description=\(ns.localizedDescription)"
        if let response = ns.userInfo[NFCISO15693TagResponseErrorKey] as? NSNumber {
            text += " tagResponse=\(response)"
        }
        if depth < 3, let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " underlying={\(errorDetails(underlying, depth: depth + 1))}"
        }
        // Avoid dumping arbitrary userInfo (it may contain full tag identifiers).
        if let tag = tag {
            for bytes in [Array(tag.identifier), Array(tag.identifier.reversed())] {
                for separator in ["", " ", ":"] {
                    let uid = bytes.map { String(format: "%02X", $0) }.joined(separator: separator)
                    if !uid.isEmpty { text = text.replacingOccurrences(of: uid, with: "[UID masked]", options: .caseInsensitive) }
                }
            }
        }
        return text
    }
    private func failureMessage(_ label: String, _ error: Error) -> String {
        let details = errorDetails(error)
        if details.localizedCaseInsensitiveContains("stack") {
            return "\(label)：NFC Stack Error；已读信息保留。停止本次操作，不写入、不自动重试。请保留版本、命令 flags 与 domain/code 日志，核对 iOS/CoreNFC 自定义命令和安装签名环境；连接成功不证明全部 NFC 权限正常。"
        }
        if let nfc = error as? NFCReaderError, nfc.code == .readerTransceiveErrorTagConnectionLost {
            return "\(label)：标签连接丢失。请保持手机顶部与卡片贴合，并持续按住 A 电源键及滚轮；此错误不等于 AD Stack Error，不自动重试。"
        }
        return "\(label)：\(error.localizedDescription)；已读取信息保留，详情见诊断日志"
    }
    private func begin(frame: Data?) {
        queue.async {
            guard !self.running else { return }
            guard NFCTagReaderSession.readingAvailable else {
                self.publish { self.status = "CoreNFC 不可用：请检查真机、签名与 NFC 权限" }; return
            }
            do { self.packets = try frame.map { try FrameCodec.packets($0) } ?? [] }
            catch { self.publish { self.status = error.localizedDescription }; return }
            self.approvedUID = nil
            self.packetIndex = 0
            self.wrote = false
            self.detected = false
            self.running = true
            self.generation = UUID()
            self.publish { self.busy = true; self.progress = 0; self.status = "请将 iPhone 顶部靠近卡片线圈"; self.identity = nil }
            guard let s = NFCTagReaderSession(pollingOption: .iso15693, delegate: self, queue: self.queue) else {
                self.finish("无法创建 NFC 会话", error: true); return
            }
            self.session = s
            s.alertMessage = frame == nil ? "只读识别 ST25DV；不会写卡" : "持续给卡片供电，保持手机顶部贴合"
            let run = self.generation
            let deadline = DispatchWorkItem { [weak self] in
                guard let self = self, self.running, self.generation == run else { return }
                self.finish("会话达到 55 秒上限", error: true)
            }
            self.wholeTimeout = deadline
            self.queue.asyncAfter(deadline: .now()+55, execute: deadline)
            self.log(frame == nil ? "v0.2.0 (3) 开始只读会话；不自动写入" : "v0.2.0 (3) 开始一次整图传输；无自动重试")
            s.begin()
        }
    }
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        guard self.session === session, running else { return }
        log("会话失效：\(errorDetails(error))")
        finish(failureMessage("NFC 会话结束", error), error: true)
    }
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard self.session === session, running, !detected else { return }
        guard tags.count == 1 else { finish("检测到多张标签，请只保留一张", error: true); return }
        guard case let .iso15693(t) = tags[0] else { finish("不支持的标签类型；仅接受 ISO15693", error: true); return }
        detected = true
        perform("连接", operation: { done in
            session.connect(to: tags[0]) { error in
                done(error.map { .failure($0) } ?? .success(()))
            }
        }, then: { (_: Void) in
            guard t.icManufacturerCode == 0x02 else { self.finish("非 ST 厂商，拒绝写入", error: true); return }
            self.tag = t
            self.readIdentity(t)
        })
    }
    /// Nonblocking callback bridge; timeout invalidates the session. Late callbacks
    /// are discarded by generation/token, never followed by another RF command.
    private func perform<T>(_ label: String,
                            operation: (@escaping (Result<T, Error>) -> Void) -> Void,
                            recover: ((Error) -> Void)? = nil,
                            then: @escaping (T) -> Void) {
        guard running, pending == nil else { return }
        let token = UUID(), run = generation
        pending = token
        log(label)
        let timer = DispatchWorkItem { [weak self] in
            guard let self = self, self.running, self.generation == run, self.pending == token else { return }
            self.finish("\(label) 超时（4 秒）；不重发命令", error: true)
        }
        timeout = timer
        queue.asyncAfter(deadline: .now()+4, execute: timer)
        operation { result in
            self.queue.async {
                guard self.running, self.generation == run, self.pending == token else { return }
                self.timeout?.cancel(); self.timeout = nil; self.pending = nil
                switch result {
                case .success(let value): then(value)
                case .failure(let error):
                    self.log("\(label) 错误：\(self.errorDetails(error))")
                    if let recover = recover { recover(error) }
                    else { self.finish(self.failureMessage(label, error), error: true) }
                }
            }
        }
    }
    private func readIdentity(_ t: NFCISO15693Tag) {
        perform("读取 System Info", operation: { done in
            t.getSystemInfo(requestFlags: self.addressed) { dsfid, afi, blockSize, blocks, icRef, error in
                if let error = error { done(.failure(error)) }
                else { done(.success((dsfid, afi, blockSize, blocks, icRef))) }
            }
        }, recover: { _ in
            self.inspectMailbox(t, info: nil)
        }, then: { (info: (Int, Int, Int, Int, Int)) in
            self.inspectMailbox(t, info: info)
        })
    }
    private func inspectMailbox(_ t: NFCISO15693Tag, info: (Int, Int, Int, Int, Int)?) {
        let raw = [UInt8](t.identifier)
        // DS10925 Rev 8, tables 83/85: IC_REF is NOT the UID product byte.
        let uid: [UInt8] = raw.count == 8 && raw[0] == 0xE0 && raw[1] == 2 ? raw :
            (raw.count == 8 && raw[7] == 0xE0 && raw[6] == 2 ? Array(raw.reversed()) : [])
        let product = uid.count == 8 ? Int(uid[2]) : -1
        var model: String?
        if let i = info {
            switch i.4 {
            case 0x24: model = "ST25DV04K 系列（封装未确认）"
            case 0x26: model = "ST25DV16K/64K 系列（容量及封装未确认）"
            default: break
            }
            // Exact capacity is claimed only if memory information is present.
            if i.2 == 4 {
                switch (product, i.3, i.4) {
                case (0x24, 128, 0x24): model = "ST25DV04K-IE"
                case (0x25, 128, 0x24): model = "ST25DV04K-JF"
                case (0x26, 512, 0x26): model = "ST25DV16K-IE"
                case (0x27, 512, 0x26): model = "ST25DV16K-JF"
                case (0x26, 2048, 0x26): model = "ST25DV64K-IE"
                case (0x27, 2048, 0x26): model = "ST25DV64K-JF"
                default: break
                }
            }
        }
        let details = info.map { i -> String in
            let memory = i.2 < 0 || i.3 < 0 ? "容量字段未返回（不是读取失败）" : "块=\(i.3)×\(i.2)"
            let reference = i.4 < 0 ? "ICRef 未返回" : String(format: "ICRef=%d (0x%02X)", i.4, i.4)
            return "DSFID=\(i.0) AFI=\(i.1) \(memory) \(reference)"
        } ?? "System Info 不可用；型号未确认"
        let masked = raw.prefix(2).map { String(format: "%02X", $0) }.joined() + "…（已遮蔽）"
        let name = model ?? "未确认型号的 ST ISO15693"
        let summary = "\(name)\nUID（API 原序）\(masked)\n\(details)"
        log("\(name)；\(details)")
        // Publish before optional AD probe; failures must not erase readable facts.
        let partial = CardIdentity(uid: t.identifier, summary: summary + "\n邮箱未确认；禁止发送", knownModel: model != nil, mailboxReady: false)
        publish { self.identity = partial; self.status = "已识别标签，正在检查邮箱…" }
        guard model != nil else {
            finish("型号未确认，已阻止写入。请在设置 → 新设备检测查看日志；不会向未知标签发送图像或使能配置。", error: true); return
        }
        readStatus { mb in
            guard mb.enabled else { self.finish("已读到标签；邮箱未启用。本 App 不自动使能或写配置；请核对卡端固件运行状态。", error: true); return }
            guard !mb.hostPending, !mb.rfPending, !mb.missed else {
                self.finish("已读到标签；邮箱不空或有丢消息标志，拒绝清除或发送", error: true); return
            }
            let found = CardIdentity(uid: t.identifier, summary: summary + "\n邮箱已启用且空闲", knownModel: model != nil, mailboxReady: true)
            if self.packets.isEmpty {
                self.publish { self.identity = found }
                self.finish("只读识别完成，请确认卡片和固件兼容性", error: false)
            } else {
                self.approvedUID = found.uid
                self.publish { self.identity = found; self.status = "型号与邮箱检查通过，开始发送…" }
                self.sendNext()
            }
        }
    }
    private func command(_ code: Int, _ parameters: Data, then: @escaping (Data) -> Void) {
        guard let tag = tag else { finish("标签已断开", error: true); return }
        // ST iOS SDK example: NON-ADDRESSED only, no UID/manufacturer in payload.
        // Standard getSystemInfo retains its own addressed flags.
        perform(String(format: "命令 %02X · flags=02 · 参数 %d 字节", code, parameters.count), operation: { done in
            tag.customCommand(requestFlags: .highDataRate,
                              customCommandCode: code, customRequestParameters: parameters) { data, error in
                if let error = error { done(.failure(error)) } else { done(.success(data)) }
            }
        }, then: then)
    }
    private func readStatus(_ then: @escaping (MailboxStatus) -> Void) {
        command(0xAD, Data([0x0D])) { data in
            // CoreNFC returns custom response payload, not raw Android RF flags.
            guard data.count == 1, let byte = data.first else {
                self.finish("动态寄存器响应长度异常：\(data.count)，不猜测偏移", error: true); return
            }
            self.log(String(format: "MB_CTRL_Dyn=%02X", byte))
            then(MailboxStatus(raw: byte))
        }
    }
    private func later(_ seconds: Double, _ action: @escaping () -> Void) {
        let run = generation
        queue.asyncAfter(deadline: .now()+seconds) {
            guard self.running, self.generation == run else { return }; action()
        }
    }
    private func sendNext() {
        guard running else { return }
        guard let approvedUID = approvedUID, let tag = tag,
              approvedUID == tag.identifier else {
            finish("当前标签未通过本会话安全检查，拒绝写入", error: true); return
        }
        guard packetIndex < packets.count else {
            finish("数据发送完成（25/25），不是屏幕 ACK。请继续供电并观察刷新，至少等待 3 秒。", error: false)
            return
        }
        readStatus { mb in
            guard mb.enabled, !mb.hostPending, !mb.rfPending, !mb.missed else {
                self.finish("发包前邮箱状态异常；停止，不覆盖消息", error: true); return
            }
            // AA parameters contain only length-minus-one + 200 bytes.
            // CoreNFC inserts manufacturer code; no flags/UID/CRC in parameters.
            self.wrote = true // An errored response may still have delivered bytes.
            self.command(0xAA, self.packets[self.packetIndex]) { _ in
                self.packetIndex += 1
                let count = self.packetIndex
                self.publish { self.progress = count; self.status = "已发送 \(count)/25 包；正在核对邮箱" }
                self.session?.alertMessage = "已发送 \(count)/25 包，请保持贴合"
                self.later(0.020) { self.awaitConsumed(until: ProcessInfo.processInfo.systemUptime+2) }
            }
        }
    }
    private func awaitConsumed(until deadline: TimeInterval) {
        readStatus { mb in
            guard mb.enabled, !mb.hostPending, !mb.missed else {
                self.finish("邮箱禁用、HOST 占用或丢消息；不执行破坏性复位", error: true); return
            }
            if mb.rfPending {
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    self.finish("卡端 2 秒内未取走消息；拒绝清空仍待消费的邮箱", error: true); return
                }
                self.later(0.020) { self.awaitConsumed(until: deadline) }
            } else { self.resetEmptyMailbox() }
        }
    }
    /// Compatibility experiment: APK delays 20ms then resets unconditionally.
    /// We refuse to drop pending data: wait for RF_PUT_MSG=0, then toggle MB_EN.
    /// This is mailbox control ONLY, NOT the MCU frame-index reset.
    private func resetEmptyMailbox() {
        command(0xAE, MailboxStatus.disable) { _ in
            self.readStatus { mb in
                guard !mb.enabled, !mb.rfPending, !mb.hostPending, !mb.missed else {
                    self.finish("邮箱禁用校验失败，停止；请断电重启", error: true); return
                }
                self.command(0xAE, MailboxStatus.enable) { _ in
                    self.readStatus { mb in
                        guard mb.enabled, !mb.rfPending, !mb.hostPending, !mb.missed else {
                            self.finish("邮箱重新使能校验失败，停止", error: true); return
                        }
                        self.sendNext()
                    }
                }
            }
        }
    }
    private func finish(_ text: String, error: Bool) {
        guard running else { return }
        running = false
        pending = nil
        timeout?.cancel(); wholeTimeout?.cancel()
        timeout = nil; wholeTimeout = nil
        let suffix = error && wrote ? "\n可能已接收部分图像；不要直接重发。断电后不按功能键，普通模式重新上电，再重新发送。" : ""
        let message = text + suffix
        log(message)
        // Keep diagnostic facts after both read-only and send sessions.
        publish { self.busy = false; self.status = message }
        // Snapshot before another run; state must not be consulted from main queue.
        if error { session?.invalidate(errorMessage: String(text.prefix(120))) }
        else { session?.alertMessage = text; session?.invalidate() }
        session = nil; tag = nil
    }
}
