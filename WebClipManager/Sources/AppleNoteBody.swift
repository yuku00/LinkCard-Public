import Foundation
import zlib

// Field mapping ported from apple_cloud_notes_parser (MIT); see ThirdParty and NOTICE.
// shortcut: only NoteStoreProto.document.note.note_text; no rich runs or embedded objects.
enum AppleNoteBody {
    static let limit = 2 * 1024 * 1024

    static func decode(_ compressed: Data) throws -> String {
        let bytes = try gunzip(compressed)
        let document = try field(2, in: bytes)
        let note = try field(3, in: document)
        let text = try field(2, in: note)
        guard let value = String(data: text, encoding: .utf8) else {
            throw ClipError.invalid("正文不是有效 UTF-8")
        }
        return value
    }

    static func gunzip(_ input: Data) throws -> Data {
        guard input.count >= 2, input.count <= limit,
              input[input.startIndex] == 0x1f, input[input.startIndex + 1] == 0x8b else {
            throw ClipError.invalid("不是支持的 gzip 正文或超过 2 MiB")
        }
        var stream = z_stream()
        guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ClipError.invalid("无法初始化 gzip")
        }
        defer { inflateEnd(&stream) }
        return try input.withUnsafeBytes { raw -> Data in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: raw.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(input.count)
            var output = Data()
            var chunk = [UInt8](repeating: 0, count: 32 * 1024)
            while true {
                let code = chunk.withUnsafeMutableBytes { buffer -> Int32 in
                    stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress!
                    stream.avail_out = uInt(buffer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let count = chunk.count - Int(stream.avail_out)
                guard output.count + count <= limit else { throw ClipError.invalid("解压正文超过 2 MiB") }
                output.append(contentsOf: chunk.prefix(count))
                if code == Z_STREAM_END {
                    guard stream.avail_in == 0 else { throw ClipError.invalid("gzip 存在额外数据") }
                    return output
                }
                guard code == Z_OK, count > 0 else { throw ClipError.invalid("gzip 损坏或截断") }
            }
        }
    }

    static func field(_ wanted: UInt64, in data: Data) throws -> Data {
        let bytes = [UInt8](data)
        var offset = 0
        func invalid() -> ClipError { .invalid("不支持或损坏的 protobuf 正文") }
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for index in 0..<10 {
                guard offset < bytes.count else { throw invalid() }
                let byte = bytes[offset]; offset += 1
                if index == 9 && byte > 1 { throw invalid() }
                value |= UInt64(byte & 0x7f) << (index * 7)
                if byte & 0x80 == 0 { return value }
            }
            throw invalid()
        }
        var result: Data?
        while offset < bytes.count {
            let key = try varint()
            let number = key >> 3
            guard number > 0, number <= 536_870_911 else { throw invalid() }
            let wire = key & 7
            if number == wanted && wire != 2 { throw invalid() }
            var length = 0
            switch wire {
            case 0: _ = try varint()
            case 1: length = 8
            case 2:
                let n = try varint()
                guard n <= UInt64(bytes.count - offset) else { throw invalid() }
                length = Int(n)
            case 5: length = 4
            default: throw invalid()
            }
            guard length <= bytes.count - offset else { throw invalid() }
            if number == wanted {
                guard result == nil else { throw invalid() }
                result = Data(bytes[offset..<(offset + length)])
            }
            offset += length
        }
        guard let result = result else { throw invalid() }
        return result
    }
}
