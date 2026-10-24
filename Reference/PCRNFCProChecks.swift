// SPDX-License-Identifier: GPL-3.0-or-later
// Run on a Swift host: swiftc LinkCard/PCRProtocol.swift Reference/PCRNFCProChecks.swift -o /tmp/pcr-info-checks && /tmp/pcr-info-checks
import Foundation

@main struct PCRNFCProChecks {
    static func main() {
        precondition(PCRRoute.isNFCPro("PCR-NFCPRO(BLE)"))
        precondition(PCRRoute.isNFCPro("PCR-NFCPRO"))
        for name in ["PCR-NFCPRO(BLE)", "PCR-NFCPRO", "PCR-NFCPRO(BLE) clone", "pcr-nfcpro(ble)"] {
            precondition(!PCRRoute.allowsText(name))
        }
        precondition(!PCRRoute.isNFCPro("PCR-NFCPRO(BLE) clone"))
        precondition(PCRDeviceInformation.fields.map { $0.uuid } == ["2A24", "2A27", "2A28", "2A29"])
        precondition(PCRDeviceInformation.displayValue(Data("PCR-NFCPRO".utf8)) == "PCR-NFCPRO")
        precondition(PCRDeviceInformation.displayValue(Data(" v1.2 ".utf8)) == "v1.2")
        precondition(PCRDeviceInformation.displayValue(Data("厂商".utf8)) == "厂商")
        for data in [Data(), Data([0xff]), Data(repeating: 65, count: 129), Data("v1\nsecret".utf8), Data("v1\u{202e}abc".utf8)] {
            precondition(PCRDeviceInformation.displayValue(data) == "无有效文本（原值不展示）")
        }
        for text in ["SerialNumber:test", "UID:test", "token:test", "password:test", "序列号:test", "   "] {
            precondition(PCRDeviceInformation.displayValue(Data(text.utf8)) == "字段已隐藏（空值或敏感标记）")
        }
        precondition(PCRDeviceInformation.displayValue(nil) == "无有效文本（原值不展示）")
        precondition(PCRDeviceInformation.displayValue(Data(repeating: 65, count: 100)).count == 80)
        print("PCR NFCPRO routing and standard information checks passed")
    }
}
