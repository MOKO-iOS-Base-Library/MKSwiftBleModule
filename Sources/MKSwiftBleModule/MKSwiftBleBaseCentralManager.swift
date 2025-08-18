import Foundation
import CoreBluetooth

enum MKSwiftCurrentAction {
    case idle
    case scan
    case connecting
}

 
@MainActor public final class MKSwiftBleBaseCentralManager: NSObject {
    
    public static let shared = MKSwiftBleBaseCentralManager()
    
    // MARK: - Properties
    
    public private(set) var centralManager: CBCentralManager!
    public private(set) var currentManager: (any MKSwiftBleCentralManagerProtocol)?
    public private(set) var connectStatus: MKSwiftPeripheralConnectState = .unknown
    public private(set) var centralStatus: MKSwiftCentralManagerState = .unable
    
    private(set) var managerAction: MKSwiftCurrentAction = .idle
    private var peripheralManager: MKSwiftBlePeripheralProtocol?
    private var centralManagerQueue: DispatchQueue
    private var connectTimeout = false
    private var isConnecting = false
    private let operationQueue = OperationQueue()
        
    private var timeoutTask: Task<Void, Never>?
    private var connectContinuation: CheckedContinuation<CBPeripheral, Error>?
    
    // MARK: - Initialization
    
    private override init() {
        centralManagerQueue = DispatchQueue(label: "moko.com.centralManager")
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: centralManagerQueue)
        operationQueue.maxConcurrentOperationCount = 1
    }
    
    // MARK: - Public Methods
    
    public func peripheral() -> CBPeripheral? {
        peripheralManager?.peripheral
    }
    
    public func configCentralManager(_ dataManager: MKSwiftBleCentralManagerProtocol) {
        currentManager = nil
        currentManager = dataManager
    }
    
    public func removeCentralManager() {
        currentManager = nil
    }
    
    // MARK: - Scanning
    
    @discardableResult public func scanForPeripherals(withServices services: [CBUUID]?, options: [String: Any]? = nil) -> Bool {
        if centralManager.state != .poweredOn || managerAction == .connecting || currentManager == nil {
            return false
        }
        
        if managerAction == .scan {
            centralManager.stopScan()
        }
        
        managerAction = .scan
        
        DispatchQueue.main.async { [weak self] in
            self?.currentManager?.centralManagerStartScan()
        }
        
        centralManager.scanForPeripherals(withServices: services, options: options)
        return true
    }
    
    @discardableResult public func stopScan() -> Bool {
        if centralManager.state != .poweredOn || managerAction == .connecting || currentManager == nil {
            return false
        }
        if managerAction == .scan {
            centralManager.stopScan()
        }
        
        managerAction = .idle
        
        DispatchQueue.main.async { [weak self] in
            self?.currentManager?.centralManagerStopScan()
        }
        
        return true
    }
    
    // MARK: - Connection
    
    public func connectDevice(_ peripheralProtocol: MKSwiftBlePeripheralProtocol) async throws -> CBPeripheral {
        try await connectWithProtocol(peripheralProtocol)
    }
    
    public func disconnect() {
        guard centralManager.state == .poweredOn,
              let peripheral = peripheralManager?.peripheral else {
            return
        }
        
        operationQueue.cancelAllOperations()
        centralManager.cancelPeripheralConnection(peripheral)
        peripheralManager = nil
        isConnecting = false
    }
    
    // MARK: - Data Communication
    
    @discardableResult public func sendDataToPeripheral(_ data: String,
                                    characteristic: CBCharacteristic,
                                    type: CBCharacteristicWriteType) -> Bool {
        guard let peripheral = peripheralManager?.peripheral,
              !data.isEmpty,
              peripheral.state == .connected else {
            return false
        }
        let commandData = MKSwiftBleSDKAdopter.stringToData(data)
        guard !commandData.isEmpty else {
            return false
        }
        
        peripheral.writeValue(commandData, for: characteristic, type: type)
        return true
    }
    
    public var readyToCommunication: Bool {
        peripheralManager?.peripheral != nil && connectStatus == .connected
    }
    
    @discardableResult public func addOperation(_ operation: Operation & MKSwiftBleOperationProtocol) -> Bool {
        guard !operationQueue.operations.contains(where: { $0 === operation }) else {
            return false
        }
        operationQueue.addOperation(operation)
        return true
    }
    
    @discardableResult public func removeOperation(_ operation: Operation & MKSwiftBleOperationProtocol) -> Bool {
        guard operationQueue.operations.contains(where: { $0 === operation }) else {
            return false
        }
        if operation.isExecuting {
            operation.cancel()
        }
        return true
    }
    
    // MARK: - Private Methods
    
    private func updateCentralManagerState() {
        let stateCopy = centralManager.state == .poweredOn ? MKSwiftCentralManagerState.enable : .unable
        
        NotificationCenter.default.post(
            name: .swiftCentralManagerStateChanged,
            object: nil,
            userInfo: ["state": stateCopy]
        )
        
        if currentManager != nil {
            currentManager?.centralManagerStateChanged(stateCopy)
        }
        
        centralStatus = stateCopy
        
        if centralManager.state == .poweredOn {
            return
        }
        
        switch managerAction {
        case .idle:
            if connectStatus == .connected {
                updatePeripheralConnectState(.disconnect)
            }
            peripheralManager?.setNil()
            peripheralManager = nil
            
        case .scan:
            stopScan()
            
        case .connecting:
            connectPeripheralFailed()
        }
    }
    
    private func connectWithProtocol(_ peripheralProtocol: MKSwiftBlePeripheralProtocol) async throws -> CBPeripheral {
        guard centralManager.state == .poweredOn else {
            throw MKSwiftBleError.bluetoothPowerOff
        }
        
        if isConnecting {
            throw MKSwiftBleError.connecting
        }
        
        await MainActor.run {
            isConnecting = true
        }
        
        // 取消已有连接
        if let existingPeripheral = peripheralManager?.peripheral {
            centralManager.cancelPeripheralConnection(existingPeripheral)
        }
        
        // 重置状态
        peripheralManager?.setNil()
        peripheralManager = nil
        peripheralManager = peripheralProtocol
        managerAction = .connecting
        
        // 停止扫描
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        
        // 更新连接状态
        updatePeripheralConnectState(.connecting)
        
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else { return }
            
            Task {@MainActor in
                // 存储continuation
                self.connectContinuation = continuation
                
                // 开始连接
                self.centralManager.connect(peripheralProtocol.peripheral, options: nil)
                
                // 启动超时检测
                self.timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: 20 * 1_000_000_000)
                        await MainActor.run {
                            guard let self = self else { return }
                            self.connectTimeout = true
                            self.connectContinuation?.resume(throwing: MKSwiftBleError.connectFailed)
                            self.resetOriSettings()
                        }
                    } catch {
                        // 忽略取消错误
                    }
                }
            }
        }
    }
    
    private func resetOriSettings() {
        timeoutTask?.cancel()
        timeoutTask = nil
        managerAction = .idle
        connectContinuation = nil
        isConnecting = false
        connectTimeout = false
    }
    
    private func connectPeripheralFailed() {
        connectContinuation?.resume(throwing: MKSwiftBleError.connectFailed)
        resetOriSettings()
        
        if let peripheral = peripheralManager?.peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        peripheralManager?.setNil()
        peripheralManager = nil
        
        updatePeripheralConnectState(.connectedFailed)
    }
    
    private func connectPeripheralSuccess() {
        guard !connectTimeout, peripheralManager != nil else { return }
        
        if let peripheral = self.peripheralManager?.peripheral {
            connectContinuation?.resume(returning: peripheral)
        }
        
        resetOriSettings()
        updatePeripheralConnectState(.connected)
    }
    
    private func updatePeripheralConnectState(_ state: MKSwiftPeripheralConnectState) {
        connectStatus = state
        NotificationCenter.default.post(name: .swiftPeripheralConnectStateChanged, object: nil)
        currentManager?.peripheralConnectStateChanged(state)
    }
}

// MARK: - CBCentralManagerDelegate

@MainActor extension MKSwiftBleBaseCentralManager: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { [weak self] in
            self?.updateCentralManagerState()
        }
    }
    
    public func centralManager(_ central: CBCentralManager,
                              didDiscover peripheral: CBPeripheral,
                              advertisementData: [String: Any],
                              rssi RSSI: NSNumber) {
        guard RSSI.intValue != 127 else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.currentManager?.centralManagerDiscoverPeripheral(peripheral,
                                                  advertisementData: advertisementData,
                                                  rssi: RSSI)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !connectTimeout,
              peripheralManager != nil,
              managerAction == .connecting else {
            return
        }
        
        peripheral.delegate = self
        peripheralManager?.setNil()
        peripheralManager?.discoverServices()
    }
    
    public func centralManager(_ central: CBCentralManager,
                              didFailToConnect peripheral: CBPeripheral,
                              error: Error?) {
        Task { [weak self] in
            self?.connectPeripheralFailed()
        }
    }
    
    public func centralManager(_ central: CBCentralManager,
                              didDisconnectPeripheral peripheral: CBPeripheral,
                              error: Error?) {
        print("---------->The peripheral is disconnect")
        guard connectStatus == .connected else { return }
        
        operationQueue.cancelAllOperations()
        Task { [weak self] in
            self?.peripheralManager?.setNil()
            self?.peripheralManager = nil
            self?.updatePeripheralConnectState(.disconnect)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension MKSwiftBleBaseCentralManager: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard !connectTimeout,
              peripheralManager != nil,
              managerAction == .connecting else {
            return
        }
        
        if error != nil {
            Task { [weak self] in
                self?.connectPeripheralFailed()
            }
            return
        }
        
        peripheralManager?.setNil()
        peripheralManager?.discoverCharacteristics()
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                          didDiscoverCharacteristicsFor service: CBService,
                          error: Error?) {
        guard !connectTimeout,
              peripheralManager != nil,
              managerAction == .connecting else {
            return
        }
        
        if error != nil {
            Task { [weak self] in
                self?.connectPeripheralFailed()
            }
            return
        }
        
        peripheralManager?.updateCharacter(with: service)
        if peripheralManager?.connectSuccess == true {
            Task { [weak self] in
                self?.connectPeripheralSuccess()
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                          didUpdateNotificationStateFor characteristic: CBCharacteristic,
                          error: Error?) {
        guard error == nil,
              !connectTimeout,
              peripheralManager != nil,
              managerAction == .connecting else {
            return
        }
        
        peripheralManager?.updateCurrentNotifySuccess(characteristic)
        if peripheralManager?.connectSuccess == true {
            Task { [weak self] in
                self?.connectPeripheralSuccess()
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                          didUpdateValueFor characteristic: CBCharacteristic,
                          error: Error?) {
        guard error == nil else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.currentManager?.peripheral(peripheral, didUpdateValueFor: characteristic, error: error)
            self?.operationQueue.operations
                .compactMap { $0 as? (Operation & MKSwiftBleOperationProtocol) }
                .first { $0.isExecuting }?
                .peripheral(peripheral, didUpdateValueFor: characteristic)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                          didWriteValueFor characteristic: CBCharacteristic,
                          error: Error?) {
        guard error == nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.currentManager?.peripheral(peripheral, didWriteValueFor: characteristic, error: error)
            self?.operationQueue.operations
                .compactMap { $0 as? (Operation & MKSwiftBleOperationProtocol) }
                .first { $0.isExecuting }?
                .peripheral(peripheral, didWriteValueFor: characteristic)
        }
    }
}
