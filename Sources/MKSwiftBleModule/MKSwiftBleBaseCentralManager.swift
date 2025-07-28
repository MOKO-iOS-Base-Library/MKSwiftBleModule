import Foundation

import CoreBluetooth

enum MKSwiftCurrentAction {
    case `default`
    case scan
    case connecting
}

public class MKSwiftBleBaseCentralManager: NSObject {
    
    // MARK: - Properties
    
    public private(set) var centralManager: CBCentralManager!
    public private(set) var managerList = [MKSwiftBleCentralManagerProtocol]()
    public private(set) var connectStatus: MKSwiftPeripheralConnectState = .unknown
    public private(set) var centralStatus: MKSwiftCentralManagerState = .unable
    
    @MainActor public static let shared = MKSwiftBleBaseCentralManager()
    private(set) var managerAction: MKSwiftCurrentAction = .default
    private var peripheralManager: MKSwiftBlePeripheralProtocol?
    private var centralManagerQueue: DispatchQueue
    private var connectTimer: DispatchSourceTimer?
    private var connectFailBlock: ((Error) -> Void)?
    private var connectSucBlock: ((CBPeripheral) -> Void)?
    private var connectTimeout = false
    private var isConnecting = false
    private let operationQueue = OperationQueue()
    
    private let defaultConnectTime: TimeInterval = 20.0
    
    // MARK: - Initialization
    
    private override init() {
        centralManagerQueue = DispatchQueue(label: "moko.com.centralManager")
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: centralManagerQueue)
        operationQueue.maxConcurrentOperationCount = 1
    }
    
    // MARK: - Public Methods
    
    public func peripheral() -> CBPeripheral? {
        return peripheralManager?.peripheral
    }
    
    public func loadDataManager(_ dataManager: MKSwiftBleCentralManagerProtocol) {
        if !self.managerList.contains(where: { $0 === dataManager }) {
            self.managerList.append(dataManager)
        }
    }
    
    @discardableResult
    public func removeDataManager(_ dataManager: MKSwiftBleCentralManagerProtocol) -> Bool {
        if let index = self.managerList.firstIndex(where: { $0 === dataManager }) {
            self.managerList.remove(at: index)
        }
        return true
    }
    
    // MARK: - Scanning
    
    @discardableResult
    public func scanForPeripherals(withServices services: [CBUUID]?, options: [String: Any]? = nil) -> Bool {
        if centralManager.state != .poweredOn {
            return false
        }
        
        if managerAction == .scan {
            centralManager.stopScan()
        } else if managerAction == .connecting {
            connectPeripheralFailed()
        }
        
        managerAction = .scan
        
        self.managerList.forEach {
            $0.centralManagerStartScan()
        }
        
        centralManager.scanForPeripherals(withServices: services, options: options)
        return true
    }
    
    @discardableResult
    public func stopScan() -> Bool {
        if managerAction == .scan {
            centralManager.stopScan()
        } else if managerAction == .connecting {
            connectPeripheralFailed()
        }
        
        managerAction = .default
        
        self.managerList.forEach {
            $0.centralManagerStopScan()
        }
        
        return true
    }
    
    // MARK: - Connection
    
    public func connectDevice(_ peripheralProtocol: MKSwiftBlePeripheralProtocol,
                             sucBlock: ((CBPeripheral) -> Void)?,
                             failedBlock: ((Error) -> Void)?) {
        if centralManager.state != .poweredOn {
            failedBlock?(MKSwiftBleError.bluetoothPowerOff)
            return
        }
        
        if isConnecting {
            failedBlock?(MKSwiftBleError.connecting)
            return
        }
        
        operationQueue.cancelAllOperations()
        isConnecting = true
        
        connectWithProtocol(peripheralProtocol) { [weak self] peripheral in
            self?.clearConnectBlock()
            sucBlock?(peripheral)
        } failedBlock: { [weak self] error in
            self?.clearConnectBlock()
            failedBlock?(error)
        }
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
    
    @discardableResult
    public func sendDataToPeripheral(_ data: String,
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
        guard let _ = peripheralManager?.peripheral else {
            return false
        }
        return connectStatus == .connected
    }
    
    @discardableResult
    public func addOperation(_ operation: Operation & MKSwiftBleOperationProtocol) -> Bool {
        guard !operationQueue.operations.contains(where: { $0 === operation }) else {
            return false
        }
        operationQueue.addOperation(operation)
        return true
    }
    
    @discardableResult
    public func removeOperation(_ operation: Operation & MKSwiftBleOperationProtocol) -> Bool {
        guard operationQueue.operations.contains(where: { $0 === operation }) else {
            return false
        }
        operation.cancel()
        return true
    }
    
    // MARK: - Private Methods
    
    private func updateCentralManagerState() {
        let managerState: MKSwiftCentralManagerState = (centralManager.state == .poweredOn ? .enable : .unable)
        centralStatus = managerState
        
        NotificationCenter.default.post(name: .swiftCentralManagerStateChanged, object: nil)
        self.managerList.forEach {
            $0.centralManagerStateChanged(managerState)
        }
        
        if centralManager.state == .poweredOn {
            return
        }
        
        switch managerAction {
        case .default:
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
    
    private func connectWithProtocol(_ peripheralProtocol: MKSwiftBlePeripheralProtocol,
                                    sucBlock: @escaping (CBPeripheral) -> Void,
                                    failedBlock: @escaping (Error) -> Void) {
        if let existingPeripheral = peripheralManager?.peripheral {
            centralManager.cancelPeripheralConnection(existingPeripheral)
        }
        peripheralManager?.setNil()
        peripheralManager = nil
        
        peripheralManager = peripheralProtocol
        managerAction = .connecting
        connectSucBlock = sucBlock
        connectFailBlock = failedBlock
        
        centralConnectPeripheral(peripheralProtocol.peripheral)
    }
    
    private func centralConnectPeripheral(_ peripheral: CBPeripheral) {
        guard peripheralManager != nil else { return }
        
        centralManager.stopScan()
        updatePeripheralConnectState(.connecting)
        initConnectTimer()
        centralManager.connect(peripheral, options: nil)
    }
    
    private func initConnectTimer() {
        connectTimeout = false
        connectTimer = DispatchSource.makeTimerSource(queue: centralManagerQueue)
        connectTimer?.schedule(deadline: .now() + defaultConnectTime, repeating: defaultConnectTime)
        
        connectTimer?.setEventHandler { [weak self] in
            self?.connectTimeout = true
            self?.connectPeripheralFailed()
        }
        
        connectTimer?.resume()
    }
    
    private func resetOriSettings() {
        connectTimer?.cancel()
        connectTimer = nil
        managerAction = .default
        connectTimeout = false
        isConnecting = false
    }
    
    private func connectPeripheralFailed() {
        resetOriSettings()
        
        if let peripheral = peripheralManager?.peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        peripheralManager?.setNil()
        peripheralManager = nil
        
        updatePeripheralConnectState(.connectedFailed)
        
        self.connectFailBlock?(MKSwiftBleError.connectFailed)
    }
    
    private func connectPeripheralSuccess() {
        guard !connectTimeout, peripheralManager != nil else { return }
        
        resetOriSettings()
        updatePeripheralConnectState(.connected)
        
        if let peripheral = self.peripheralManager?.peripheral {
            self.connectSucBlock?(peripheral)
        }
    }
    
    private func updatePeripheralConnectState(_ state: MKSwiftPeripheralConnectState) {
        connectStatus = state
        
        NotificationCenter.default.post(name: .swiftPeripheralConnectStateChanged, object: nil)
        self.managerList.forEach {
            $0.peripheralConnectStateChanged(state)
        }
    }
    
    private func clearConnectBlock() {
        connectSucBlock = nil
        connectFailBlock = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension MKSwiftBleBaseCentralManager: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateCentralManagerState()
    }
    
    public func centralManager(_ central: CBCentralManager,
                              didDiscover peripheral: CBPeripheral,
                              advertisementData: [String: Any],
                              rssi RSSI: NSNumber) {
        guard RSSI.intValue != 127, !managerList.isEmpty else { return }
        
        self.managerList.forEach {
            $0.centralManagerDiscoverPeripheral(peripheral,
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
        connectPeripheralFailed()
    }
    
    public func centralManager(_ central: CBCentralManager,
                              didDisconnectPeripheral peripheral: CBPeripheral,
                              error: Error?) {
        print("---------->The peripheral is disconnect")
        guard connectStatus == .connected else { return }
        
        operationQueue.cancelAllOperations()
        peripheralManager?.setNil()
        peripheralManager = nil
        updatePeripheralConnectState(.disconnect)
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
            connectPeripheralFailed()
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
            connectPeripheralFailed()
            return
        }
        
        peripheralManager?.updateCharacter(with: service)
        if peripheralManager?.connectSuccess == true {
            connectPeripheralSuccess()
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
            connectPeripheralSuccess()
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                          didUpdateValueFor characteristic: CBCharacteristic,
                          error: Error?) {
        guard error == nil else { return }
        
        managerList.forEach {
            $0.peripheral(peripheral, didUpdateValueFor: characteristic, error: error)
        }
        operationQueue.operations
            .compactMap { $0 as? (Operation & MKSwiftBleOperationProtocol) }
            .first { $0.isExecuting }?
            .peripheral(peripheral, didUpdateValueFor: characteristic)
    }

    public func peripheral(_ peripheral: CBPeripheral,
                          didWriteValueFor characteristic: CBCharacteristic,
                          error: Error?) {
        guard error == nil else { return }
        managerList.forEach {
            $0.peripheral(peripheral, didWriteValueFor: characteristic, error: error)
        }
        operationQueue.operations
            .compactMap { $0 as? (Operation & MKSwiftBleOperationProtocol) }
            .first { $0.isExecuting }?
            .peripheral(peripheral, didWriteValueFor: characteristic)
    }
}
