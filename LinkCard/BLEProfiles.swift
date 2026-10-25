// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Compiled-in adapters only. Profiles contain data, never executable code or commands.
protocol DeviceAdapter {
    var id: String { get }
    var title: String { get }
    func permitsVersion(advertisedName: String) -> Bool
}
struct ConnectOnlyAdapter: DeviceAdapter {
    let id = "connect-only"
    let title = "仅连接 / 服务发现（未知协议）"
    func permitsVersion(advertisedName: String) -> Bool { false }
}
struct PCRTextAdapter: DeviceAdapter {
    let id = "pcr-text-v1"
    let title = "PCR 文本版本（已有静态证据，精确型号门禁）"
    func permitsVersion(advertisedName: String) -> Bool { PCRRoute.allowsText(advertisedName) }
}
enum DeviceAdapters {
    static let registered: [any DeviceAdapter] = [ConnectOnlyAdapter(), PCRTextAdapter()]
    static func adapter(_ id: String) -> (any DeviceAdapter)? { registered.first { $0.id == id } }
    static let pcrChannels = [
        ["FF00", "FF02", "FF01"],
        ["6E400001-B5A3-F393-E0A9-E50E24DCCA9E", "6E400002-B5A3-F393-E0A9-E50E24DCCA9E", "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"]
    ]
}
struct BLEProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var namePrefix: String
    var serviceUUID: String
    var writeUUID: String
    var notifyUUID: String
    var adapterID: String
    static let builtin = BLEProfile(id: UUID(uuidString: "C940C080-868C-4C26-9393-A85023F43D90")!, name: "PCR 已验证文本 / 通道候选", namePrefix: "PCR", serviceUUID: "", writeUUID: "", notifyUUID: "", adapterID: "pcr-text-v1")
    static func validUUID(_ value: String) -> Bool {
        guard let range = value.range(of: "^(?:[0-9A-Fa-f]{4}|[0-9A-Fa-f]{8}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})$", options: .regularExpression) else { return false }
        return range == (value.startIndex..<value.endIndex)
    }
    static func canonicalUUID(_ value: String) -> String {
        let upper = value.uppercased()
        if upper.count == 4 { return "0000" + upper + "-0000-1000-8000-00805F9B34FB" }
        if upper.count == 8 { return upper + "-0000-1000-8000-00805F9B34FB" }
        return upper
    }
    static func sameUUID(_ lhs: String, _ rhs: String) -> Bool {
        validUUID(lhs) && validUUID(rhs) && canonicalUUID(lhs) == canonicalUUID(rhs)
    }
    /// Diagnostic/persistence keys only; retain vendor-specific 128-bit UUIDs intact.
    static func displayUUID(_ value: String) -> String {
        let upper = canonicalUUID(value)
        if upper.hasPrefix("0000"), upper.hasSuffix("-0000-1000-8000-00805F9B34FB"), upper.count == 36 {
            return String(upper.dropFirst(4).prefix(4))
        }
        return upper
    }
    var validationError: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80, namePrefix.count <= 80,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !namePrefix.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return "名称不能为空、超过 80 字符或包含控制字符。" }
        guard DeviceAdapters.adapter(adapterID) != nil else { return "协议适配器未实现。" }
        if id == Self.builtin.id { return self == Self.builtin ? nil : "内置配置不能覆盖。" }
        guard !namePrefix.isEmpty || !serviceUUID.isEmpty else { return "至少填写广播名前缀或服务 UUID。" }
        guard [serviceUUID, writeUUID, notifyUUID].allSatisfy({ $0.isEmpty || Self.validUUID($0) }) else { return "UUID 必须为 4/8 位十六进制或标准 128 位 UUID。" }
        guard (writeUUID.isEmpty && notifyUUID.isEmpty) || (!serviceUUID.isEmpty && !writeUUID.isEmpty && !notifyUUID.isEmpty) else { return "通道须同时填写服务、写入、通知 UUID；仅连接可只填发现线索。" }
        guard writeUUID.isEmpty || Self.canonicalUUID(writeUUID) != Self.canonicalUUID(notifyUUID) else { return "写入与通知特征必须不同。" }
        if adapterID == "pcr-text-v1", !DeviceAdapters.pcrChannels.contains(where: { $0.map(Self.canonicalUUID) == [serviceUUID, writeUUID, notifyUUID].map(Self.canonicalUUID) }) { return "PCR 文本适配器仅接受已有证据的 FF00 或 Nordic UART 通道。" }
        return nil
    }
    var channels: [[String]] {
        if id == Self.builtin.id { return DeviceAdapters.pcrChannels }
        return writeUUID.isEmpty ? [] : [[serviceUUID, writeUUID, notifyUUID]]
    }
    func matches(name: String, services: [String]) -> Bool {
        (!namePrefix.isEmpty && name.uppercased().hasPrefix(namePrefix.uppercased())) ||
        (!serviceUUID.isEmpty && services.contains(where: { Self.canonicalUUID($0) == Self.canonicalUUID(serviceUUID) })) ||
        (id == Self.builtin.id && services.contains(where: { value in DeviceAdapters.pcrChannels.contains { Self.canonicalUUID($0[0]) == Self.canonicalUUID(value) } }))
    }
}
struct BLETrust: Identifiable, Codable, Equatable {
    var id: UUID // CBPeripheral.identifier, not an authentication credential
    var profileID: UUID
}
struct BLEPreferences: Codable {
    var formatVersion = 1
    var autoScan = true
    var showDiscoveryPrompt = true
    var profiles = [BLEProfile.builtin]
    /// Array order is explicit user priority; never choose by RSSI/name.
    var trusted = [BLETrust]()
    private static let key = "linkcard.ble.preferences.v1"
    /// Never encoded. A failed restore must not silently erase/overwrite saved consent.
    private(set) var restorationWarning: String?
    private enum CodingKeys: String, CodingKey { case formatVersion, autoScan, showDiscoveryPrompt, profiles, trusted }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        // Older records may omit optional settings; missing consent fails closed.
        autoScan = try values.decodeIfPresent(Bool.self, forKey: .autoScan) ?? false
        showDiscoveryPrompt = try values.decodeIfPresent(Bool.self, forKey: .showDiscoveryPrompt) ?? false
        profiles = try values.decode([BLEProfile].self, forKey: .profiles)
        trusted = try values.decode([BLETrust].self, forKey: .trusted)
    }
    private static func restoreFailed() -> Self {
        var value = Self()
        value.autoScan = false; value.showDiscoveryPrompt = false
        value.restorationWarning = "已保存的蓝牙设置暂时无法恢复；原数据已保留，自动连接与设置保存已暂停。可临时手动连接，请勿重置应用数据。"
        return value
    }
    static func load(from defaults: UserDefaults = .standard) -> BLEPreferences {
        guard defaults.object(forKey: key) != nil else { return Self() }
        guard let data = defaults.data(forKey: key), data.count <= 131072,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.formatVersion == 1,
              value.profiles.count <= 33, value.trusted.count <= 100,
              value.profiles.contains(.builtin), value.profiles.allSatisfy({ $0.validationError == nil }),
              Set(value.profiles.map(\.id)).count == value.profiles.count,
              Set(value.trusted.map(\.id)).count == value.trusted.count,
              value.trusted.allSatisfy({ trust in value.profiles.contains { $0.id == trust.profileID } }) else { return restoreFailed() }
        return value
    }
    @discardableResult
    func save(to defaults: UserDefaults = .standard) -> Bool {
        guard restorationWarning == nil, let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.key)
        return defaults.data(forKey: Self.key) == data
    }
}

/// Typed persistence boundary: the coordinator cannot store card/device payloads.
struct BLEPreferencesStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> BLEPreferences { BLEPreferences.load(from: defaults) }
    func save(_ preferences: BLEPreferences) -> Bool { preferences.save(to: defaults) }
}
