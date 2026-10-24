// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Input is the upright, row-major preview (white=255, black=0).
enum FrameCodec {
    static func encode(_ pixels: [UInt8]) throws -> Data {
        guard pixels.count == 40_000 else { throw CardError.message("图像必须为 200×200") }
        var bytes = [UInt8](repeating: 0, count: 5_000)
        for y in 0..<200 {
            for x in 0..<200 where pixels[(199-y)*200+x] > 100 {
                bytes[y*25+x/8] |= UInt8(1 << (7-x%8))
            }
        }
        return Data(bytes)
    }
    static func packets(_ frame: Data) throws -> [Data] {
        guard frame.count == 5_000 else { throw CardError.message("帧长度不是 5000 字节") }
        return stride(from: 0, to: 5_000, by: 200).map {
            Data([0xC7]) + frame.subdata(in: $0..<($0+200))
        }
    }
}
enum CardError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

struct MailboxStatus {
    let raw: UInt8
    var enabled: Bool { raw & 1 != 0 }
    var hostPending: Bool { raw & 2 != 0 }
    var rfPending: Bool { raw & 4 != 0 }
    var missed: Bool { raw & 0x30 != 0 }
    // Only MB_EN is writable. Never echo RO/miss/current/reserved bits.
    static let disable = Data([0x0D, 0x00])
    static let enable = Data([0x0D, 0x01])
}
