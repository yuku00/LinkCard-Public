// Deterministic transport double. Used only by host regression checks, never linked into the app.
import Foundation
public enum CBManagerAuthorization { case allowedAlways, denied, restricted, notDetermined }
public enum CBManagerState { case poweredOn, poweredOff, unauthorized, unsupported, unknown }
public enum CBCharacteristicWriteType { case withResponse, withoutResponse }
public let CBCentralManagerOptionShowPowerAlertKey = "power"
public let CBCentralManagerScanOptionAllowDuplicatesKey = "duplicates"
public let CBAdvertisementDataLocalNameKey = "name"
public let CBAdvertisementDataServiceUUIDsKey = "services"
public let CBAdvertisementDataOverflowServiceUUIDsKey = "overflow"
public protocol CBCentralManagerDelegate: AnyObject {}
public protocol CBPeripheralDelegate: AnyObject {}
public final class CBUUID: NSObject {
    public let uuidString: String
    public init(string: String) { uuidString = string.uppercased() }
    public override func isEqual(_ object: Any?) -> Bool { (object as? CBUUID)?.uuidString == uuidString }
    public override var hash: Int { uuidString.hashValue }
}
public struct CBCharacteristicProperties: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let read = Self(rawValue: 1)
    public static let write = Self(rawValue: 2)
    public static let writeWithoutResponse = Self(rawValue: 4)
    public static let notify = Self(rawValue: 8)
    public static let indicate = Self(rawValue: 16)
}
public final class CBCharacteristic {
    public let uuid: CBUUID
    public let properties: CBCharacteristicProperties
    public var value: Data?
    public var isNotifying = false
    public init(_ uuid: String, _ properties: CBCharacteristicProperties, value: String = "") {
        self.uuid = CBUUID(string: uuid); self.properties = properties; self.value = Data(value.utf8)
    }
}
public final class CBService {
    public let uuid: CBUUID
    public var characteristics: [CBCharacteristic]?
    public init(_ uuid: String, _ characteristics: [CBCharacteristic]) {
        self.uuid = CBUUID(string: uuid); self.characteristics = characteristics
    }
}
public final class CBPeripheral {
    public let identifier: UUID
    public var name: String?
    public weak var delegate: CBPeripheralDelegate?
    public var services: [CBService]?
    public var canSendWriteWithoutResponse = true
    public var reads = [CBCharacteristic]()
    public var writes = [Data]()
    public var subscriptions = 0
    public init(name: String, services: [CBService], identifier: UUID = UUID()) { self.name = name; self.services = services; self.identifier = identifier }
    public func discoverServices(_ uuids: [CBUUID]?) {}
    public func discoverCharacteristics(_ uuids: [CBUUID]?, for service: CBService) {}
    public var writeLimit = 20
    public func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int { writeLimit }
    public func readValue(for characteristic: CBCharacteristic) { reads.append(characteristic) }
    public func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) { writes.append(data) }
    public func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) { characteristic.isNotifying = enabled; subscriptions += 1 }
}
public final class CBCentralManager {
    public static var authorization: CBManagerAuthorization = .allowedAlways
    public static var latest: CBCentralManager!
    public var state: CBManagerState = .poweredOn
    public var cancellations = 0
    public var connections = 0
    public var scans = 0
    public init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?, options: [String: Any]?) { Self.latest = self }
    public func stopScan() {}
    public func scanForPeripherals(withServices: [CBUUID]?, options: [String: Any]?) { scans += 1 }
    public func connect(_ peripheral: CBPeripheral, options: [String: Any]?) { connections += 1 }
    public func cancelPeripheralConnection(_ peripheral: CBPeripheral) { cancellations += 1 }
}
