import Foundation
import CoreBluetooth

// MARK: - 状态枚举
public enum MKSwiftPeripheralConnectState: Sendable {
    case unknown
    case connecting
    case connected
    case connectedFailed
    case disconnect
}

public enum MKSwiftCentralManagerState: Sendable {
    case unable
    case enable
}

// MARK: - 通知名称
public extension Notification.Name {
    static let swiftPeripheralConnectStateChanged = Notification.Name("MKSwiftPeripheralConnectStateChangedNotification")
    static let swiftCentralManagerStateChanged = Notification.Name("MKSwiftCentralManagerStateChangedNotification")
}

// MARK: - 协议定义

// 扫描协议
public protocol MKSwiftBleScanProtocol: AnyObject, Sendable {
    func centralManagerDiscoverPeripheral(_ peripheral: CBPeripheral,
                                        advertisementData: [String: Any],
                                        rssi: NSNumber)
    
    func centralManagerStartScan()
    func centralManagerStopScan()
}

extension MKSwiftBleScanProtocol {
    // 提供默认实现使方法可选
    func centralManagerStartScan() {}
    func centralManagerStopScan() {}
}

// 状态协议
public protocol MKSwiftBleCentralManagerStateProtocol: AnyObject, Sendable {
    func centralManagerStateChanged(_ state: MKSwiftCentralManagerState)
    func peripheralConnectStateChanged(_ state: MKSwiftPeripheralConnectState)
}

// 中央管理器协议（组合扫描+状态）
public protocol MKSwiftBleCentralManagerProtocol: MKSwiftBleScanProtocol, MKSwiftBleCentralManagerStateProtocol {
    func peripheral(_ peripheral: CBPeripheral,
                   didUpdateValueFor characteristic: CBCharacteristic,
                   error: Error?)
    
    func peripheral(_ peripheral: CBPeripheral,
                   didWriteValueFor characteristic: CBCharacteristic,
                   error: Error?)
}

// 外设协议
public protocol MKSwiftBlePeripheralProtocol: AnyObject, Sendable {
    var peripheral: CBPeripheral { get }
    func discoverServices()
    func discoverCharacteristics()
    func updateCharacter(with service: CBService)
    func updateCurrentNotifySuccess(_ characteristic: CBCharacteristic)
    var connectSuccess: Bool { get }
    func setNil()
}

// 操作协议
public protocol MKSwiftBleOperationProtocol: AnyObject, Sendable {
    func peripheral(_ peripheral: CBPeripheral,
                   didUpdateValueFor characteristic: CBCharacteristic)
    
    func peripheral(_ peripheral: CBPeripheral,
                   didWriteValueFor characteristic: CBCharacteristic)
}
