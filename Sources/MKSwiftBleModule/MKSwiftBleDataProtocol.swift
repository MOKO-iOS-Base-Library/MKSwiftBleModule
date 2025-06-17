//
//  File.swift
//  MKSwiftBleModule
//
//  Created by aa on 2025/5/18.
//

import Foundation

import CoreBluetooth

// MARK: - 状态枚举
public enum MKSwiftPeripheralConnectState {
    case unknown
    case connecting
    case connected
    case connectedFailed
    case disconnect
}

public enum MKSwiftCentralManagerState {
    case unable
    case enable
}

// MARK: - 通知名称
public extension Notification.Name {
    static let swiftPeripheralConnectStateChanged = Notification.Name("MKSwiftPeripheralConnectStateChangedNotification")
    static let swiftCentralManagerStateChanged = Notification.Name("MKSwiftCentralManagerStateChangedNotification")
}

// MARK: - 回调类型
typealias MKSwiftBleConnectFailedBlock = (Error) -> Void
typealias MKSwiftBleConnectSuccessBlock = (CBPeripheral) -> Void

// MARK: - 协议定义

// 扫描协议
public protocol MKSwiftBleScanProtocol: AnyObject {
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
public protocol MKSwiftBleCentralManagerStateProtocol: AnyObject {
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
public protocol MKSwiftBlePeripheralProtocol: AnyObject {
    var peripheral: CBPeripheral { get }
    func discoverServices()
    func discoverCharacteristics()
    func updateCharacter(with service: CBService)
    func updateCurrentNotifySuccess(_ characteristic: CBCharacteristic)
    var connectSuccess: Bool { get }
    func setNil()
}

// 操作协议
public protocol MKSwiftBleOperationProtocol: AnyObject {
    func peripheral(_ peripheral: CBPeripheral,
                   didUpdateValueFor characteristic: CBCharacteristic)
    
    func peripheral(_ peripheral: CBPeripheral,
                   didWriteValueFor characteristic: CBCharacteristic)
}
