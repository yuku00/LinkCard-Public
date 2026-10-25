// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// Independently implemented from observed framing, not vendor implementation.
enum PCRProtocolError: Error { case malformed, overflow, deviceError }
struct PCRTextReply {
    private var bytes = Data()
    mutating func feed(_ data: Data) throws -> String? {
        bytes.append(data)
        guard bytes.count <= 4096 else { throw PCRProtocolError.overflow }
        guard let text = String(data: bytes, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        guard lines.count >= 2 else { return nil }
        let header = lines[0]
        guard header.count >= 4, header.dropFirst(3).first == ":",
              let code = Int(header.prefix(3)) else { throw PCRProtocolError.malformed }
        guard code == 100 || code == 101 else { throw PCRProtocolError.deviceError }
        guard lines.count >= 3 else { return nil }
        // Never expose the raw reply, which may contain SerialNumb/UID/tokens.
        // Only an explicitly labelled dotted version number is displayed.
        let pattern = #"(?i)(?:version|firmware|ver|版本)\s*[:=v ]\s*(\d{1,3}(?:\.\d{1,3}){1,3})(?![\d.])"#
        let body = lines.dropFirst().joined(separator: " ")
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
           let range = Range(match.range(at: 1), in: body) {
            return "版本 \(body[range])（设备自报，未认证）"
        }
        return "收到有效版本响应（状态 \(code)）；未识别安全版本字段，原文不展示。"
    }
}

// Offline tested only. No runtime route sends PN53x until model/mode evidence exists.
struct PCRPN53xReply {
    private var bytes = [UInt8]()
    private var ack = false
    mutating func feed(_ data: Data) throws -> [UInt8]? {
        bytes.append(contentsOf: data)
        guard bytes.count <= 300 else { throw PCRProtocolError.overflow }
        if !ack {
            guard bytes.count >= 6 else { return nil }
            guard Array(bytes.prefix(6)) == [0, 0, 255, 0, 255, 0] else { throw PCRProtocolError.malformed }
            bytes.removeFirst(6); ack = true
        }
        guard bytes.count >= 5 else { return nil }
        guard Array(bytes.prefix(3)) == [0, 0, 255],
              (Int(bytes[3]) + Int(bytes[4])) & 255 == 0,
              bytes[3] >= 2, bytes[3] != 255 else { throw PCRProtocolError.malformed }
        let length = Int(bytes[3])
        guard bytes.count >= length + 7 else { return nil }
        guard bytes.count == length + 7, bytes[5] == 0xD5, bytes[6] == 3,
              bytes[length + 6] == 0,
              bytes[5...length + 5].reduce(0, { $0 + Int($1) }) & 255 == 0,
              length == 6 else { throw PCRProtocolError.malformed }
        return Array(bytes[7..<11])
    }
}

enum PCRRoute {
    static let textNames: Set<String> = ["PcrGP_V2.0", "PcrGP_V2.0(BLE)", "PcrGP3.0(BLE)",
        "PcrGP4_OLED", "PcrGP3.0UL(BLE)", "PcrGP3.0UL", "PcrGP3.0_Pro(BLE)",
        "PcrGP3.0_Pro", "NFCTOOLS(BLE)", "NFCTOOLMAX(BLE)"]
    static func allowsText(_ advertisedName: String) -> Bool { textNames.contains(advertisedName) }
    static func isNFCPro(_ advertisedName: String) -> Bool {
        ["PCR-NFCPRO(BLE)", "PCR-NFCPRO"].contains(advertisedName)
    }
    static func explanation(for advertisedName: String) -> String {
        if isNFCPro(advertisedName) {
            return "已识别 PCR-NFCPRO（厂商类型 -3、PN532 HAL），不是 PCRPANDA 文本型号。可点击识别卡片启用易失性读卡模式；标准设备信息仍通过 180A 独立读取，不自动发送业务命令。"
        }
        return "型号／模式证据不足，业务版本查询未开放；可手动读取已提供的 180A 标准信息。"
    }
}

/// Standard Device Information only; deliberately excludes serial/system identifiers.
enum PCRDeviceInformation {
    static let fields: [(uuid: String, label: String)] = [
        ("2A24", "型号"), ("2A27", "硬件版本"),
        ("2A28", "软件版本"), ("2A29", "厂商")
    ]
    static func displayValue(_ data: Data?) -> String {
        guard let data = data, !data.isEmpty, data.count <= 128,
              let text = String(data: data, encoding: .utf8) else { return "无有效文本（原值不展示）" }
        // Reject control/bidi/invisible formatting and labelled sensitive identifiers.
        guard text.unicodeScalars.allSatisfy({
            !CharacterSet.controlCharacters.contains($0) &&
            $0.properties.generalCategory != .format
        }) else { return "无有效文本（原值不展示）" }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        guard !value.isEmpty, !["serial", "uid", "token", "password", "序列号"].contains(where: { lower.contains($0) }) else {
            return "字段已隐藏（空值或敏感标记）"
        }
        return String(value.prefix(80))
    }
}
