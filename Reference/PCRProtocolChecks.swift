// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main struct PCRProtocolChecks {
    static func require(_ value: Bool, _ message: String) {
        if !value { fatalError(message) }
    }
    static func rejects(_ action: () throws -> Void) {
        do { try action(); fatalError("Expected rejection") } catch { }
    }
    static func main() throws {
        let text = Data("101:OK WITH TEXT\r\nFirmware: 2.3.4 SerialNumb:[PRIVATE]\r\n".utf8)
        for split in 0...text.count {
            var parser = PCRTextReply()
            let first = try parser.feed(Data(text.prefix(split)))
            let result = try first ?? parser.feed(Data(text.dropFirst(split)))
            require(result == "版本 2.3.4（设备自报，未认证）", "Text split \(split)")
            require(!(result ?? "").contains("PRIVATE"), "Privacy")
        }
        var bytewise = PCRTextReply(); var answer: String?
        for byte in text { answer = try bytewise.feed(Data([byte])) }
        require(answer != nil, "Bytewise text")
        rejects { var p = PCRTextReply(); _ = try p.feed(Data("200:ERROR\r\n".utf8)) }
        rejects { var p = PCRTextReply(); _ = try p.feed(Data("bad\r\n".utf8)) }
        rejects { var p = PCRTextReply(); _ = try p.feed(Data(repeating: 65, count: 4097)) }
        var partial = PCRTextReply()
        require(try partial.feed(Data("101:OK WITH TEXT\r\nVersion: 1.2".utf8)) == nil, "Need terminator")
        var privateReply = PCRTextReply()
        let redacted = try privateReply.feed(Data("101:OK WITH TEXT\r\nSerialNumb:[SECRET]\r\n".utf8))
        require(!(redacted ?? "").contains("SECRET"), "Never expose raw reply")
        let ack: [UInt8] = [0, 0, 255, 0, 255, 0]
        let frame: [UInt8] = [0, 0, 255, 6, 250, 213, 3, 50, 1, 6, 7, 232, 0]
        let packet = Data(ack + frame)
        for split in 0...packet.count {
            var parser = PCRPN53xReply()
            let first = try parser.feed(Data(packet.prefix(split)))
            let result = try first ?? parser.feed(Data(packet.dropFirst(split)))
            require(result == [50, 1, 6, 7], "Binary split \(split)")
        }
        for index in [0, 3, 4, 5, 6, 9, 10, 11, 12, 17, 18] {
            var damaged = Array(packet); damaged[index] ^= 1
            rejects { var p = PCRPN53xReply(); _ = try p.feed(Data(damaged)) }
        }
        rejects { var p = PCRPN53xReply(); _ = try p.feed(Data(frame)) }
        rejects { var p = PCRPN53xReply(); _ = try p.feed(packet + Data([0])) }
        rejects { var p = PCRPN53xReply(); _ = try p.feed(Data(repeating: 0, count: 301)) }
        require(PCRRoute.allowsText("PcrGP_V2.0(BLE)"), "Known exact route")
        for name in ["PcrReader(BLE)", "PCR-NFCPRO(BLE)", "ChameleonUltra", "PcrGP_V2.0(BLE) fake", "DfuTarg", "Pixl.js"] {
            require(!PCRRoute.allowsText(name), "No guessing: \(name)")
        }
        print("PASS: actual Swift parsers; all text/binary split points, bytewise text, ACK/LCS/DCS/TFI/command/overflow rejection, redaction and exact routes. No BLE hardware exercised.")
    }
}
