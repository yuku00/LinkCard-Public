// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Independently implemented from NXP UM0701-02 §§6.2, 7.2.10, 7.3.1, 7.3.5.
/// This adapter has no arbitrary transceive, authentication, memory read or write API.
enum PN532Error: Error { case malformed, overflow, nak, deviceError, unexpected }
enum PN532Frame: Equatable { case ack, response(UInt8, [UInt8]) }
struct PN532Stream {
    private var bytes = [UInt8]()
    mutating func feed(_ data: Data) throws -> [PN532Frame] {
        guard bytes.count + data.count <= 1024 else { throw PN532Error.overflow }
        bytes.append(contentsOf: data)
        var frames = [PN532Frame]()
        while !bytes.isEmpty {
            guard bytes.count >= 3 else { break }
            guard Array(bytes.prefix(3)) == [0, 0, 0xFF] else { throw PN532Error.malformed }
            guard bytes.count >= 6 else { break }
            if bytes[3] == 0 && bytes[4] == 0xFF {
                guard bytes[5] == 0 else { throw PN532Error.malformed }
                frames.append(.ack); bytes.removeFirst(6); continue
            }
            if bytes[3] == 0xFF && bytes[4] == 0 {
                guard bytes[5] == 0 else { throw PN532Error.malformed }
                throw PN532Error.nak // Fail closed; never retransmit automatically.
            }
            // These short commands never need extended responses. Reject explicitly.
            guard bytes[3] != 0xFF, bytes[3] > 0,
                  (Int(bytes[3]) + Int(bytes[4])) & 255 == 0 else { throw PN532Error.malformed }
            let length = Int(bytes[3]), total = length + 7
            guard bytes.count >= total else { break }
            guard bytes[total - 1] == 0,
                  bytes[5...(length + 5)].reduce(0, { $0 + Int($1) }) & 255 == 0 else { throw PN532Error.malformed }
            if length == 1 && bytes[5] == 0x7F { throw PN532Error.deviceError }
            guard length >= 2, bytes[5] == 0xD5 else { throw PN532Error.malformed }
            frames.append(.response(bytes[6], Array(bytes[7..<(5 + length)])))
            bytes.removeFirst(total)
        }
        return frames
    }
    var isEmpty: Bool { bytes.isEmpty }
}
struct PN532Exchange {
    let command: UInt8
    private var stream = PN532Stream()
    private var acknowledged = false
    private var completed = false
    init(command: UInt8) { self.command = command }
    mutating func feed(_ data: Data) throws -> [UInt8]? {
        guard !completed else { throw PN532Error.unexpected }
        let frames = try stream.feed(data)
        var reply: [UInt8]?
        for frame in frames {
            guard reply == nil else { throw PN532Error.unexpected }
            switch frame {
            case .ack:
                guard !acknowledged else { throw PN532Error.unexpected }
                acknowledged = true
            case let .response(code, payload):
                guard acknowledged, code == command &+ 1 else { throw PN532Error.unexpected }
                reply = payload
            }
        }
        if reply != nil {
            guard stream.isEmpty else { throw PN532Error.unexpected }
            completed = true
        }
        return reply
    }
}
struct PN532Card: Equatable {
    let uid: [UInt8]
    let atqa: [UInt8] // Wire order: MSB then LSB, not silently reversed.
    let sak: UInt8
    var uidHex: String { uid.map { String(format: "%02X", $0) }.joined(separator: " ") }
    var maskedUID: String { Array(repeating: "••", count: uid.count).joined(separator: " ") }
    var atqaHex: String { atqa.map { String(format: "%02X", $0) }.joined() }
    var sakHex: String { String(format: "%02X", sak) }
    var candidate: String {
        if sak & 0x20 != 0 { return "ISO 14443-4 / CPU 卡候选" }
        switch sak {
        case 0x00: return "Ultralight / NTAG 等 Type A 候选"
        case 0x08: return "MIFARE Classic 1K 兼容候选"
        case 0x18: return "MIFARE Classic 4K 兼容候选"
        case 0x09: return "MIFARE Mini 兼容候选"
        default: return "ISO 14443A · 未确定具体类型"
        }
    }
    static func parse(_ p: [UInt8]) throws -> PN532Card? {
        if p == [0] { return nil }
        guard p.count >= 6, p[0] == 1, p[1] == 1,
              [4, 7, 10].contains(Int(p[5])), p[4] & 0x04 == 0 else { throw PN532Error.malformed }
        let end = 6 + Int(p[5])
        guard p.count >= end else { throw PN532Error.malformed }
        if p[4] & 0x20 != 0 {
            guard p.count > end, p[end] >= 1, p[end] <= 20,
                  p.count == end + Int(p[end]) else { throw PN532Error.malformed }
        } else if p.count != end { throw PN532Error.malformed }
        return PN532Card(uid: Array(p[6..<end]), atqa: Array(p[2...3]), sak: p[4])
    }
}
enum NFCProIdentify {
    static let ack = Data([0, 0, 0xFF, 0, 0xFF, 0])
    static let wake = Data([0x55, 0x55, 0, 0, 0, 0, 0])
    // All configuration below is PN532 runtime state, not card/flash/EEPROM writes.
    enum Step: CaseIterable { case sam, retries, poll, fieldOff
        var command: UInt8 {
            switch self { case .sam: return 0x14; case .poll: return 0x4A; default: return 0x32 }
        }
        var parameters: [UInt8] {
            switch self {
            case .sam: return [0x01, 0x14, 0x01] // Normal, no SAM; timeout only applies in Virtual mode.
            case .retries: return [0x05, 0x00, 0x00, 0x01] // Finite passive activation, never FF.
            case .poll: return [0x01, 0x00] // One target, 106 kbit/s ISO14443A.
            case .fieldOff: return [0x01, 0x00]
            }
        }
        var packet: Data { NFCProIdentify.frame(command, parameters) }
        var timeout: Double { self == .poll ? 4 : 2 }
    }
    static func frame(_ command: UInt8, _ parameters: [UInt8]) -> Data {
        let body: [UInt8] = [0xD4, command] + parameters
        let length = UInt8(body.count)
        let checksum = UInt8(truncatingIfNeeded: -body.reduce(0, { $0 + Int($1) }))
        return Data([0, 0, 0xFF, length, 0 &- length] + body + [checksum, 0])
    }
    static func permits(name: String, builtinProfile: Bool, channel: [String], model: String?) -> Bool {
        guard builtinProfile, PCRRoute.isNFCPro(name), channel == ["FF00", "FF02", "FF01"] else { return false }
        // 180A is optional, but an explicitly conflicting model is not ignored.
        return model == nil || model == "TD5322A"
    }
}
