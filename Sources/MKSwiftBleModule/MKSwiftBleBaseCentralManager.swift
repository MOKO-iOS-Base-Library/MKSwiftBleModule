import Foundation
@preconcurrency import CoreBluetooth

enum MKSwiftCurrentAction: Sendable {
    case idle
    case scan
    case connecting
}

// MARK: - Main Central Manager Implementation
public final class MKSwiftBleBaseCentralManager: NSObject, @unchecked Sendable {
    public static let shared = MKSwiftBleBaseCentralManager()
    
    // MARK: - Thread-Safe State Container
    
    private final class State: @unchecked Sendable {
        private let queue = DispatchQueue(label: "moko.com.state", attributes: .concurrent)
        
        // Backing storage
        private var _connectStatus: MKSwiftPeripheralConnectState = .unknown
        private var _centralStatus: MKSwiftCentralManagerState = .unable
        private var _managerAction: MKSwiftCurrentAction = .idle
        private var _isConnecting = false
        private var _connectTimeout = false
        private var _peripheralManager: (any MKSwiftBlePeripheralProtocol & Sendable)?
        private var _currentManager: (any MKSwiftBleCentralManagerProtocol & Sendable)?
        
        // Thread-safe accessors
        var connectStatus: MKSwiftPeripheralConnectState {
            get { queue.sync { _connectStatus } }
            set { queue.async(flags: .barrier) { self._connectStatus = newValue } }
        }
        
        var centralStatus: MKSwiftCentralManagerState {
            get { queue.sync { _centralStatus } }
            set { queue.async(flags: .barrier) { self._centralStatus = newValue } }
        }
        
        var managerAction: MKSwiftCurrentAction {
            get { queue.sync { _managerAction } }
            set { queue.async(flags: .barrier) { self._managerAction = newValue } }
        }
        
        var isConnecting: Bool {
            get { queue.sync { _isConnecting } }
            set { queue.async(flags: .barrier) { self._isConnecting = newValue } }
        }
        
        var connectTimeout: Bool {
            get { queue.sync { _connectTimeout } }
            set { queue.async(flags: .barrier) { self._connectTimeout = newValue } }
        }
        
        var peripheralManager: (any MKSwiftBlePeripheralProtocol & Sendable)? {
            get { queue.sync { _peripheralManager } }
            set { queue.async(flags: .barrier) { self._peripheralManager = newValue } }
        }
        
        var currentManager: (any MKSwiftBleCentralManagerProtocol & Sendable)? {
            get { queue.sync { _currentManager } }
            set { queue.async(flags: .barrier) { self._currentManager = newValue } }
        }
    }
    
    // MARK: - Properties
    
    private let state = State()
    private let operationQueue = OperationQueue()
    private let centralManagerQueue: DispatchQueue
    private let _centralManager: CBCentralManager
    private var timeoutTask: Task<Void, Never>?
    private let continuationLock = NSLock()
    private var _connectContinuation: CheckedContinuation<CBPeripheral, Error>?
    
    // Public interface
    public var centralManager: CBCentralManager { _centralManager }
    
    public private(set) var connectStatus: MKSwiftPeripheralConnectState {
        get { state.connectStatus }
        set { state.connectStatus = newValue }
    }
    
    public private(set) var centralStatus: MKSwiftCentralManagerState {
        get { state.centralStatus }
        set { state.centralStatus = newValue }
    }
    
    private var managerAction: MKSwiftCurrentAction {
        get { state.managerAction }
        set { state.managerAction = newValue }
    }
    
    private var isConnecting: Bool {
        get { state.isConnecting }
        set { state.isConnecting = newValue }
    }
    
    private var connectTimeout: Bool {
        get { state.connectTimeout }
        set { state.connectTimeout = newValue }
    }
    
    private var peripheralManager: (any MKSwiftBlePeripheralProtocol & Sendable)? {
        get { state.peripheralManager }
        set { state.peripheralManager = newValue }
    }
    
    private var currentManager: (any MKSwiftBleCentralManagerProtocol & Sendable)? {
        get { state.currentManager }
        set { state.currentManager = newValue }
    }
    
    private var connectContinuation: CheckedContinuation<CBPeripheral, Error>? {
        get { continuationLock.withLock { _connectContinuation } }
        set { continuationLock.withLock { _connectContinuation = newValue } }
    }
    
    // MARK: - Initialization
    
    private override init() {
        centralManagerQueue = DispatchQueue(label: "moko.com.centralManager")
        _centralManager = CBCentralManager(delegate: nil, queue: centralManagerQueue)
        super.init()
        _centralManager.delegate = self
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.underlyingQueue = centralManagerQueue
    }
    
    // MARK: - Public Methods
    
    public func peripheral() -> CBPeripheral? {
        peripheralManager?.peripheral
    }
    
    public func configCentralManager(_ dataManager: any MKSwiftBleCentralManagerProtocol & Sendable) {
        currentManager = dataManager
    }
    
    public func removeCentralManager() {
        currentManager = nil
    }
    
    // MARK: - Scanning
    
    @discardableResult
    public func scanForPeripherals(withServices services: [CBUUID]?, options: [String: Any]? = nil) -> Bool {
        guard centralManager.state == .poweredOn,
              !isConnecting,
              currentManager != nil else {
            return false
        }
        
        if managerAction == .scan {
            centralManager.stopScan()
        }
        
        managerAction = .scan
        
        // Convert to known-safe options at call site
        let knownOptions = extractKnownScanOptions(from: options)
        
        centralManagerQueue.async {
            // Reconstruct the dictionary just before use
            var cbOptions: [String: Any]? = nil
            if let knownOptions = knownOptions {
                cbOptions = [String: Any]()
                if let allowDuplicates = knownOptions.allowDuplicates {
                    cbOptions?[CBCentralManagerScanOptionAllowDuplicatesKey] = allowDuplicates
                }
                if let solicitedServices = knownOptions.solicitedServiceUUIDs {
                    cbOptions?[CBCentralManagerScanOptionSolicitedServiceUUIDsKey] = solicitedServices
                }
            }
            
            self.centralManager.scanForPeripherals(
                withServices: services,
                options: cbOptions
            )
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.currentManager?.centralManagerStartScan()
        }
        
        return true
    }
    
    @discardableResult
    public func stopScan() -> Bool {
        guard centralManager.state == .poweredOn,
              !isConnecting,
              currentManager != nil else {
            return false
        }
        
        if managerAction == .scan {
            centralManagerQueue.async {
                self.centralManager.stopScan()
            }
        }
        
        managerAction = .idle
        
        DispatchQueue.main.async { [weak self] in
            self?.currentManager?.centralManagerStopScan()
        }
        
        return true
    }
    
    // MARK: - Connection
    
    public func connectDevice(_ peripheralProtocol: any MKSwiftBlePeripheralProtocol & Sendable) async throws -> CBPeripheral {
        try await connectWithProtocol(peripheralProtocol)
    }
    
    public func disconnect() {
        guard centralManager.state == .poweredOn,
              let peripheral = peripheralManager?.peripheral else {
            return
        }
        
        operationQueue.cancelAllOperations()
        centralManagerQueue.async {
            self.centralManager.cancelPeripheralConnection(peripheral)
        }
        
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
        
        centralManagerQueue.async {
            peripheral.writeValue(commandData, for: characteristic, type: type)
        }
        return true
    }
    
    public var readyToCommunication: Bool {
        peripheralManager?.peripheral != nil && connectStatus == .connected
    }
    
    @discardableResult
    public func addOperation(_ operation: Operation & MKSwiftBleOperationProtocol & Sendable) -> Bool {
        guard !operationQueue.operations.contains(where: { $0 === operation }) else {
            return false
        }
        operationQueue.addOperation(operation)
        return true
    }
    
    @discardableResult
    public func removeOperation(_ operation: Operation & MKSwiftBleOperationProtocol & Sendable) -> Bool {
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
        
        centralStatus = stateCopy
        DispatchQueue.main.async { [weak self] in
            self?.currentManager?.centralManagerStateChanged(stateCopy)
        }
        
        guard centralManager.state == .poweredOn else {
            handleBluetoothPoweredOff()
            return
        }
    }
    
    private func handleBluetoothPoweredOff() {
        switch connectStatus {
        case .connected:
            updatePeripheralConnectState(.disconnect)
            peripheralManager = nil
        default:
            break
        }
        
        switch managerAction {
        case .scan:
            stopScan()
        case .connecting:
            connectPeripheralFailed()
        case .idle:
            break
        }
    }
    
    private func connectWithProtocol(_ peripheralProtocol: any MKSwiftBlePeripheralProtocol & Sendable) async throws -> CBPeripheral {
        guard centralManager.state == .poweredOn else {
            throw MKSwiftBleError.bluetoothPowerOff
        }
        
        if isConnecting {
            throw MKSwiftBleError.connecting
        }
        
        isConnecting = true
        
        // Cancel existing connection if any
        if let existingPeripheral = peripheralManager?.peripheral {
            centralManagerQueue.async {
                self.centralManager.cancelPeripheralConnection(existingPeripheral)
            }
        }
        
        // Reset state
        peripheralManager = peripheralProtocol
        managerAction = .connecting
        
        // Stop scanning if needed
        if centralManager.isScanning {
            centralManagerQueue.async {
                self.centralManager.stopScan()
            }
        }
        
        // Update connection state
        updatePeripheralConnectState(.connecting)
        
        return try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            
            centralManagerQueue.async {
                self.centralManager.connect(peripheralProtocol.peripheral, options: nil)
            }
            
            // Start timeout
            self.timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 20 * 1_000_000_000)
                    await self?.handleConnectTimeout()
                } catch {
                    // Task was cancelled
                }
            }
        }
    }
    
    private func handleConnectTimeout() async {
        if !connectTimeout {
            connectTimeout = true
        }
        
        connectContinuation?.resume(throwing: MKSwiftBleError.connectFailed)
        connectContinuation = nil
        
        resetOriSettings()
    }
    
    private func resetOriSettings() {
        timeoutTask?.cancel()
        timeoutTask = nil
        
        managerAction = .idle
        isConnecting = false
        connectTimeout = false
    }
    
    private func connectPeripheralFailed() {
        connectContinuation?.resume(throwing: MKSwiftBleError.connectFailed)
        connectContinuation = nil
        
        resetOriSettings()
        
        if let peripheral = peripheralManager?.peripheral {
            centralManagerQueue.async {
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
        }
        
        peripheralManager = nil
        updatePeripheralConnectState(.connectedFailed)
    }
    
    private func connectPeripheralSuccess() {
        guard !connectTimeout, peripheralManager != nil else { return }
        
        if let peripheral = peripheralManager?.peripheral {
            connectContinuation?.resume(returning: peripheral)
            connectContinuation = nil
        }
        
        resetOriSettings()
        updatePeripheralConnectState(.connected)
    }
    
    private func updatePeripheralConnectState(_ state: MKSwiftPeripheralConnectState) {
        connectStatus = state
        
        NotificationCenter.default.post(name: .swiftPeripheralConnectStateChanged, object: nil)
        
        DispatchQueue.main.async { [weak self] in
            self?.currentManager?.peripheralConnectStateChanged(state)
        }
    }
    
    private struct KnownScanOptions: Sendable {
        let allowDuplicates: Bool?
        let solicitedServiceUUIDs: [CBUUID]?
    }

    private func extractKnownScanOptions(from options: [String: Any]?) -> KnownScanOptions? {
        guard let options = options else { return nil }
        
        return KnownScanOptions(
            allowDuplicates: options[CBCentralManagerScanOptionAllowDuplicatesKey] as? Bool,
            solicitedServiceUUIDs: options[CBCentralManagerScanOptionSolicitedServiceUUIDsKey] as? [CBUUID]
        )
    }
}

// MARK: - CBCentralManagerDelegate
extension MKSwiftBleBaseCentralManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateCentralManagerState()
    }
    
    public func centralManager(_ central: CBCentralManager,
                             didDiscover peripheral: CBPeripheral,
                             advertisementData: [String: Any],
                             rssi RSSI: NSNumber) {
        guard RSSI.intValue != 127 else { return }
        
        let discoveryInfo = MKBleAdvInfo(
                peripheralIdentifier: peripheral.identifier,
                advertisementData: advertisementData,
                rssi: RSSI
            )
            
            DispatchQueue.main.async { [weak self] in
                self?.currentManager?.centralManagerDiscoverPeripheral(peripheral, advertisementData: discoveryInfo)
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
        print("---------->The peripheral is disconnected")
        guard connectStatus == .connected else { return }
        
        operationQueue.cancelAllOperations()
        peripheralManager = nil
        updatePeripheralConnectState(.disconnect)
    }
}

// MARK: - CBPeripheralDelegate
extension MKSwiftBleBaseCentralManager: CBPeripheralDelegate {
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.currentManager?.peripheral(peripheral, didUpdateValueFor: characteristic, error: error)
            
            self.operationQueue.operations
                .compactMap { $0 as? (Operation & MKSwiftBleOperationProtocol & Sendable) }
                .first { $0.isExecuting }?
                .peripheral(peripheral, didUpdateValueFor: characteristic)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral,
                         didWriteValueFor characteristic: CBCharacteristic,
                         error: Error?) {
        guard error == nil else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.currentManager?.peripheral(peripheral, didWriteValueFor: characteristic, error: error)
            
            self.operationQueue.operations
                .compactMap { $0 as? (Operation & MKSwiftBleOperationProtocol & Sendable) }
                .first { $0.isExecuting }?
                .peripheral(peripheral, didWriteValueFor: characteristic)
        }
    }
}

// Helper extension for NSLock
extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
