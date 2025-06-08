//
//  BluetoothViewModel.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 8/8/24.
//

import Foundation
import CoreBluetooth
import CoreLocation
import Combine
import MapKit
import os.log
import SwiftUI

public let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.bluetooth.scanner",
    category: "BluetoothScanner"
)

extension CBPeripheralState {
    var description: String {
        switch self {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .disconnecting:
            return "disconnecting"
        @unknown default:
            return "unknown"
        }
    }
}

struct BluetoothDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: NSNumber
    let count: Int
    let coordinate: CLLocationCoordinate2D
    var distance: Double
    var angle: Double
    
    // Additional BLE properties
    var manufacturerData: Data?
    var serviceUUIDs: [CBUUID]?
    var isConnectable: Bool
    var txPowerLevel: NSNumber?
    var advertisementData: [String: Any]?
    var state: CBPeripheralState?
    var services: [CBService]?
    var characteristics: [CBCharacteristic]?
    var lastSeen: Date
    var firstSeen: Date
    var deviceType: String?
    var batteryLevel: Int?
    var discoveryHistory: [(timestamp: Date, rssi: Int)]
    
    var signalQuality: String {
        if rssi.intValue > -50 { return "Excellent" }
        if rssi.intValue > -60 { return "Very Good" }
        if rssi.intValue > -70 { return "Good" }
        if rssi.intValue > -80 { return "Fair" }
        return "Poor"
    }
    
    static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.rssi == rhs.rssi &&
               lhs.count == rhs.count &&
               lhs.distance == rhs.distance &&
               lhs.angle == rhs.angle &&
               lhs.isConnectable == rhs.isConnectable &&
               lhs.lastSeen == rhs.lastSeen &&
               lhs.firstSeen == rhs.firstSeen &&
               lhs.deviceType == rhs.deviceType &&
               lhs.batteryLevel == rhs.batteryLevel
    }
}

class BluetoothViewModel: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate, CLLocationManagerDelegate {
    @Published var deviceMap = [UUID: BluetoothDevice]()
    @Published var searchText = ""
    @Published var selectedRSSIFilter = RSSIFilter.all
    @Published private(set) var filteredDevices: [BluetoothDevice] = []
    @Published private(set) var totalFilteredDevices: Int = 0
    @Published var deviceLocations: [DeviceLocation] = []
    @Published var region: MKCoordinateRegion
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var selectedDevice: BluetoothDevice?
    @Published var connectionStates: [UUID: CBPeripheralState] = [:]
    @Published var characteristicValues: [CBUUID: Data] = [:]
    @Published var notifyingCharacteristics: Set<CBUUID> = []
    @Published public var connectionSettings: [UUID: ConnectionSettings] = [:]
    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    
    private var centralManager: CBCentralManager?
    private var locationManager: CLLocationManager?
    private let orientationManager = OrientationManager()
    private var updateTimer: Timer?
    private var lastUpdateTime: Date = Date()
    private let minimumUpdateInterval: TimeInterval = 2.0 // Reduced frequency to save power
    @Published var powerSavingMode: Bool = false
    private var isScanning = false
    private var lastRSSIUpdate: [UUID: NSNumber] = [:]
    private let rssiThreshold: Int = 5
    private let scanQueue = DispatchQueue(label: "com.bluetooth.scan", qos: .userInitiated)
    private var deviceUpdateQueue = DispatchQueue(label: "com.bluetooth.deviceUpdate", qos: .userInitiated)
    
    // Add new properties for connection management
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var pendingConnections: [UUID: Timer] = [:]
    private let connectionTimeout: TimeInterval = 10.0
    
    // Add new properties for characteristic management
    private var writeRequests: [CBUUID: Data] = [:]
    
    // Add new property to store discovered peripherals
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    
    // Add more known BLE services
    struct BLEServices {
        static let battery = CBUUID(string: "180F")
        static let deviceInfo = CBUUID(string: "180A")
        static let heartRate = CBUUID(string: "180D")
        static let healthThermometer = CBUUID(string: "1809")
        static let cyclingSpeedCadence = CBUUID(string: "1816")
        static let bloodPressure = CBUUID(string: "1810")
        static let currentTime = CBUUID(string: "1805")
        static let immediateAlert = CBUUID(string: "1802")
        static let linkLoss = CBUUID(string: "1803")
        static let txPower = CBUUID(string: "1804")
        static let alertNotification = CBUUID(string: "1811")
        static let phoneAlertStatus = CBUUID(string: "180E")
        static let scanParameters = CBUUID(string: "1813")
        static let userData = CBUUID(string: "181C")
        // Add the specific service UUID we're seeing
        static let garmentService = CBUUID(string: "08DA787A-C72D-11ED-AFA1-0242AC120002")
    }
    
    struct BLECharacteristics {
        static let batteryLevel = CBUUID(string: "2A19")
        static let manufacturerName = CBUUID(string: "2A29")
        static let modelNumber = CBUUID(string: "2A24")
        static let serialNumber = CBUUID(string: "2A25")
        static let firmwareRevision = CBUUID(string: "2A26")
        static let hardwareRevision = CBUUID(string: "2A27")
        static let softwareRevision = CBUUID(string: "2A28")
    }
    
    // Add service information structure
    struct ServiceInfo {
        let uuid: CBUUID
        let name: String
        let description: String
    }
    
    // Map of known services
    private let knownServices: [CBUUID: ServiceInfo] = [
        BLEServices.battery: ServiceInfo(
            uuid: BLEServices.battery,
            name: "Battery Service",
            description: "Provides battery level information"
        ),
        BLEServices.deviceInfo: ServiceInfo(
            uuid: BLEServices.deviceInfo,
            name: "Device Information",
            description: "Provides device information like manufacturer, model, etc."
        ),
        BLEServices.heartRate: ServiceInfo(
            uuid: BLEServices.heartRate,
            name: "Heart Rate Service",
            description: "Provides heart rate measurement data"
        ),
        BLEServices.healthThermometer: ServiceInfo(
            uuid: BLEServices.healthThermometer,
            name: "Health Thermometer",
            description: "Provides temperature measurement data"
        ),
        BLEServices.cyclingSpeedCadence: ServiceInfo(
            uuid: BLEServices.cyclingSpeedCadence,
            name: "Cycling Speed & Cadence",
            description: "Provides cycling metrics"
        ),
        BLEServices.bloodPressure: ServiceInfo(
            uuid: BLEServices.bloodPressure,
            name: "Blood Pressure",
            description: "Provides blood pressure measurements"
        ),
        BLEServices.currentTime: ServiceInfo(
            uuid: BLEServices.currentTime,
            name: "Current Time Service",
            description: "Provides current time information"
        ),
        BLEServices.immediateAlert: ServiceInfo(
            uuid: BLEServices.immediateAlert,
            name: "Immediate Alert",
            description: "Allows triggering immediate alerts"
        ),
        BLEServices.linkLoss: ServiceInfo(
            uuid: BLEServices.linkLoss,
            name: "Link Loss Service",
            description: "Alerts when connection is lost"
        ),
        BLEServices.txPower: ServiceInfo(
            uuid: BLEServices.txPower,
            name: "Tx Power Service",
            description: "Provides transmission power information"
        ),
        BLEServices.garmentService: ServiceInfo(
            uuid: BLEServices.garmentService,
            name: "Garment Service",
            description: "Custom service for garment connectivity"
        )
    ]
    
    // Function to get friendly name for a service
    func getServiceInfo(_ service: CBService) -> ServiceInfo {
        if let knownService = knownServices[service.uuid] {
            return knownService
        }
        return ServiceInfo(
            uuid: service.uuid,
            name: "Unknown Service",
            description: "Service UUID: \(service.uuid.uuidString)"
        )
    }
    
    // Function to get friendly name for a characteristic
    func getCharacteristicName(_ characteristic: CBCharacteristic) -> String {
        switch characteristic.uuid {
        case BLECharacteristics.batteryLevel:
            return "Battery Level"
        case BLECharacteristics.manufacturerName:
            return "Manufacturer Name"
        case BLECharacteristics.modelNumber:
            return "Model Number"
        case BLECharacteristics.serialNumber:
            return "Serial Number"
        case BLECharacteristics.firmwareRevision:
            return "Firmware Revision"
        case BLECharacteristics.hardwareRevision:
            return "Hardware Revision"
        case BLECharacteristics.softwareRevision:
            return "Software Revision"
        default:
            return "Characteristic \(characteristic.uuid.uuidString)"
        }
    }
    
    // Function to format characteristic value based on its type
    func formatCharacteristicValue(_ characteristic: CBCharacteristic) -> String {
        guard let value = characteristic.value else { return "No value" }
        
        switch characteristic.uuid {
        case BLECharacteristics.batteryLevel:
            return "\(value[0])%"
            
        case BLECharacteristics.manufacturerName,
             BLECharacteristics.modelNumber,
             BLECharacteristics.serialNumber,
             BLECharacteristics.firmwareRevision,
             BLECharacteristics.hardwareRevision,
             BLECharacteristics.softwareRevision:
            return String(data: value, encoding: .utf8) ?? "Invalid string"
            
        default:
            // For unknown characteristics, show hex and ASCII if possible
            let hex = value.map { String(format: "%02X", $0) }.joined()
            if let ascii = String(data: value, encoding: .utf8) {
                return "\(hex) (ASCII: \(ascii))"
            }
            return hex
        }
    }
    
    // Function to determine if a characteristic is readable
    func canReadCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
        return characteristic.properties.contains(.read)
    }
    
    // Function to determine if a characteristic is writable
    func canWriteCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
        return characteristic.properties.contains(.write) ||
               characteristic.properties.contains(.writeWithoutResponse)
    }
    
    // Function to determine if a characteristic supports notifications
    func canNotifyCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
        return characteristic.properties.contains(.notify) ||
               characteristic.properties.contains(.indicate)
    }
    
    public struct ConnectionSettings: Codable {
        public var mtu: Int
        public var connectionPriority: ConnectionPriority
        public var autoReconnect: Bool
        public var timeoutDuration: TimeInterval
        
        public enum ConnectionPriority: String, Codable {
            case high      // Reduced latency, increased power consumption
            case balanced  // Default
            case low      // Reduced power consumption, increased latency
        }
        
        public init(
            mtu: Int = 185,
            connectionPriority: ConnectionPriority = .balanced,
            autoReconnect: Bool = false,
            timeoutDuration: TimeInterval = 10.0
        ) {
            self.mtu = mtu
            self.connectionPriority = connectionPriority
            self.autoReconnect = autoReconnect
            self.timeoutDuration = timeoutDuration
        }
    }

    enum RSSIFilter: String, CaseIterable, Identifiable {
        case all = "RSSI: All"
        case strongSignal = "Strong (> -50)"
        case mediumSignal = "Medium (-50 to -80)"
        case weakSignal = "Weak (< -80)"
        
        var id: String { self.rawValue }
    }

    private var thermalStateObserver: NSObjectProtocol?
    
    override init() {
        self.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        super.init()
        
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.requestWhenInUseAuthorization()
        locationManager?.startUpdatingLocation()
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        // Load saved connection settings
        loadConnectionSettings()
        
        startContinuousUpdates()
        startThermalStateMonitoring()
    }

    private func startContinuousUpdates() {
        let interval = powerSavingMode ? 5.0 : 2.0 // Adjust based on power saving mode
        updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateDeviceAnglesAndDistances()
        }
        RunLoop.main.add(updateTimer!, forMode: .common)
    }
    
    private func startThermalStateMonitoring() {
        // Get initial thermal state
        self.thermalState = ProcessInfo.processInfo.thermalState
        logger.info("🌡️ Initial thermal state: \(self.thermalState.description)")
        
        // Observe thermal state changes
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let newThermalState = ProcessInfo.processInfo.thermalState
            logger.info("🌡️ Thermal state changed from \(self?.thermalState.description ?? "unknown") to: \(newThermalState.description)")
            self?.thermalState = newThermalState
        }
        
        // Log thermal state monitoring is active
        logger.info("🌡️ Thermal state monitoring started successfully")
    }
    
    deinit {
        updateTimer?.invalidate()
        updateTimer = nil
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Power Management
    
    private func cleanupDiscoveryHistory(_ history: [(timestamp: Date, rssi: Int)]) -> [(timestamp: Date, rssi: Int)] {
        let maxHistorySize = powerSavingMode ? 50 : 200 // Limit history size
        let cutoffTime = Date().addingTimeInterval(-300) // Keep only last 5 minutes
        
        let recentHistory = history.filter { $0.timestamp > cutoffTime }
        
        // If still too many, keep only the most recent
        if recentHistory.count > maxHistorySize {
            return Array(recentHistory.suffix(maxHistorySize))
        }
        
        return recentHistory
    }
    
    public func togglePowerSavingMode() {
        powerSavingMode.toggle()
        logger.info("🔋 Power saving mode: \(self.powerSavingMode ? "ON" : "OFF")")
        
        // Restart timer with new interval
        updateTimer?.invalidate()
        startContinuousUpdates()
        
        // Restart scan with new options if currently scanning
        if isScanning {
            startScan(triggerHaptic: false)
        }
    }
    
    private func updateDeviceAnglesAndDistances() {
        let currentTime = Date()
        guard currentTime.timeIntervalSince(lastUpdateTime) >= minimumUpdateInterval else { return }
        
        deviceUpdateQueue.async { [weak self] in
            guard let self = self else { return }
            
            let recentDevices = self.deviceMap.filter { currentTime.timeIntervalSince($0.value.lastSeen) < 30 }
            
            for (id, device) in recentDevices {
                let distance = self.calculateDistance(from: device.rssi)
                let angle = self.orientationManager.calculateAngleToDevice(deviceRSSI: device.rssi)
                
                let updatedDevice = BluetoothDevice(
                    id: device.id,
                    name: device.name,
                    rssi: device.rssi,
                    count: device.count,
                    coordinate: device.coordinate,
                    distance: distance,
                    angle: angle,
                    manufacturerData: device.manufacturerData,
                    serviceUUIDs: device.serviceUUIDs,
                    isConnectable: device.isConnectable,
                    txPowerLevel: device.txPowerLevel,
                    advertisementData: device.advertisementData,
                    state: device.state,
                    services: device.services,
                    characteristics: device.characteristics,
                    lastSeen: currentTime,
                    firstSeen: device.firstSeen,
                    deviceType: device.deviceType,
                    batteryLevel: device.batteryLevel,
                    discoveryHistory: device.discoveryHistory
                )
                
                DispatchQueue.main.async {
                    self.deviceMap[id] = updatedDevice
                }
            }
            
            DispatchQueue.main.async {
                self.lastUpdateTime = currentTime
                self.updateFilteredDevices()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            userLocation = location.coordinate
            updateRegion()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("❌ Failed to get user location: \(error.localizedDescription)")
    }

    func startScan(triggerHaptic: Bool = false) {
        guard let centralManager = centralManager, centralManager.state == .poweredOn else {
            logger.error("❌ Cannot start scan: Bluetooth is not ready")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if triggerHaptic {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
            
            logger.info("🔄 Starting new scan...")
            
            // Stop any existing scan
            if let manager = self.centralManager {
                manager.stopScan()
            }
            
            // Clear all existing data
            self.deviceMap.removeAll()
            self.lastRSSIUpdate.removeAll()
            self.filteredDevices.removeAll()
            self.deviceLocations.removeAll()
            self.totalFilteredDevices = 0
            self.discoveredPeripherals.removeAll()  // Clear discovered peripherals
            
            // Update UI to show empty state
            self.updateFilteredDevices()
            
            // Start a new scan with power-optimized options
            let options: [String: Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: !powerSavingMode // Disable duplicates in power saving mode
            ]
            
            // Start scanning for all devices
            logger.debug("⚙️ Starting scan with options: \(options)")
            self.isScanning = true
            
            // Add a small delay before starting the new scan
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let manager = self.centralManager {
                    manager.scanForPeripherals(
                        withServices: nil,
                        options: options
                    )
                    logger.info("✅ Scan started - All previous devices cleared")
                }
            }
        }
    }

    func calculateDistance(from rssi: NSNumber) -> Double {
        let txPower = -59 // Reference RSSI at 1 meter
        let ratio = rssi.doubleValue / Double(txPower)
        let distance = pow(10, (ratio - 1) / 2)
        return max(0.1, min(10.0, distance))
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        logger.debug("📱 Discovered device: \(peripheral.name ?? peripheral.identifier.uuidString) with RSSI: \(RSSI)")
        
        let currentTime = Date()
        let deviceId = peripheral.identifier
        
        // Store the discovered peripheral and set delegate
        discoveredPeripherals[deviceId] = peripheral
        peripheral.delegate = self
        
        // Process device update on main queue to avoid race conditions
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Create or update device
            var device: BluetoothDevice
            if let existingDevice = self.deviceMap[deviceId] {
                // Update existing device while preserving services
                device = BluetoothDevice(
                    id: deviceId,
                    name: peripheral.name ?? deviceId.uuidString,
                    rssi: RSSI,
                    count: existingDevice.count + 1,
                    coordinate: self.userLocation ?? CLLocationCoordinate2D(),
                    distance: self.calculateDistance(from: RSSI),
                    angle: self.orientationManager.calculateAngleToDevice(deviceRSSI: RSSI),
                    manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
                    serviceUUIDs: advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
                    isConnectable: advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? false,
                    txPowerLevel: advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber,
                    advertisementData: advertisementData,
                    state: peripheral.state,
                    services: existingDevice.services, // Preserve existing services
                    characteristics: existingDevice.characteristics, // Preserve existing characteristics
                    lastSeen: currentTime,
                    firstSeen: existingDevice.firstSeen,
                    deviceType: existingDevice.deviceType,
                    batteryLevel: existingDevice.batteryLevel,
                    discoveryHistory: cleanupDiscoveryHistory(
                        existingDevice.discoveryHistory + [(timestamp: currentTime, rssi: RSSI.intValue)]
                    )
                )
                logger.info("📱 Updated existing device: \(device.name) (Services: \(device.services?.count ?? 0))")
            } else {
                // Create new device
                device = BluetoothDevice(
                    id: deviceId,
                    name: peripheral.name ?? deviceId.uuidString,
                    rssi: RSSI,
                    count: 1,
                    coordinate: self.userLocation ?? CLLocationCoordinate2D(),
                    distance: self.calculateDistance(from: RSSI),
                    angle: self.orientationManager.calculateAngleToDevice(deviceRSSI: RSSI),
                    manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
                    serviceUUIDs: advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
                    isConnectable: advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? false,
                    txPowerLevel: advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber,
                    advertisementData: advertisementData,
                    state: peripheral.state,
                    services: nil,
                    characteristics: nil,
                    lastSeen: currentTime,
                    firstSeen: currentTime,
                    deviceType: self.determineDeviceType(
                        serviceUUIDs: advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
                        manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
                    ),
                    batteryLevel: nil,
                    discoveryHistory: [(timestamp: currentTime, rssi: RSSI.intValue)]
                )
                logger.info("📱 Created new device: \(device.name)")
            }
            
            // Update device map and trigger UI update
            self.deviceMap[deviceId] = device
            self.objectWillChange.send()
            
            // Update filtered devices
            self.updateFilteredDevices()
        }
    }

    private func determineDeviceType(serviceUUIDs: [CBUUID]?, manufacturerData: Data?) -> String? {
        let heartRateService = CBUUID(string: "180D")
        let batteryService = CBUUID(string: "180F")
        let deviceInfoService = CBUUID(string: "180A")
        
        if let services = serviceUUIDs {
            if services.contains(heartRateService) {
                return "Heart Rate Monitor"
            }
            if services.contains(batteryService) {
                return "Battery-Powered Device"
            }
            if services.contains(deviceInfoService) {
                return "Smart Device"
            }
        }
        
        if let data = manufacturerData {
            let manufacturerId = data.prefix(2)
            if manufacturerId == Data([0x00, 0x4C]) {
                return "Apple Device"
            }
        }
        
        return "Unknown Device"
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            logger.info("📱 Bluetooth state updated: \(central.state.rawValue)")
            switch central.state {
            case .poweredOn:
                logger.info("✅ Bluetooth is powered on")
                // Try to reconnect to devices with auto-reconnect enabled
                self.reconnectToSavedDevices()
                // Then start scanning
                self.startScan(triggerHaptic: false)
            case .poweredOff:
                logger.warning("⚠️ Bluetooth is powered off")
                if let manager = self.centralManager {
                    manager.stopScan()
                }
                self.deviceMap.removeAll()
                self.updateFilteredDevices()
            case .unauthorized:
                logger.error("❌ Bluetooth permission not granted")
            case .unsupported:
                logger.error("❌ Bluetooth is not supported on this device")
            case .resetting:
                logger.warning("⚠️ Bluetooth is resetting")
                // Stop scanning and clear devices when Bluetooth is resetting
                if let manager = self.centralManager {
                    manager.stopScan()
                }
                self.deviceMap.removeAll()
                self.updateFilteredDevices()
            case .unknown:
                logger.warning("⚠️ Bluetooth state is unknown")
            @unknown default:
                logger.warning("⚠️ Unknown Bluetooth state")
            }
        }
    }
    
    private func reconnectToSavedDevices() {
        logger.info("🔄 Checking for devices to auto-reconnect...")
        
        // Get all devices with auto-reconnect enabled
        let devicesToReconnect = connectionSettings.filter { _, settings in
            settings.autoReconnect
        }
        
        guard !devicesToReconnect.isEmpty else {
            logger.info("ℹ️ No devices found with auto-reconnect enabled")
            return
        }
        
        logger.info("🔄 Found \(devicesToReconnect.count) device(s) with auto-reconnect enabled")
        
        guard let manager = centralManager else {
            logger.error("❌ Cannot reconnect: Bluetooth manager is not available")
            return
        }
        
        // Try to retrieve and connect to each device
        for (deviceId, _) in devicesToReconnect {
            logger.info("🔄 Attempting to retrieve device: \(deviceId)")
            
            if let peripheral = manager.retrievePeripherals(withIdentifiers: [deviceId]).first {
                logger.info("✅ Retrieved peripheral \(deviceId), attempting connection...")
                
                // Store in discovered peripherals
                discoveredPeripherals[deviceId] = peripheral
                peripheral.delegate = self
                
                // Create a temporary device entry if needed
                if deviceMap[deviceId] == nil {
                    let tempDevice = BluetoothDevice(
                        id: deviceId,
                        name: peripheral.name ?? deviceId.uuidString,
                        rssi: 0,
                        count: 1,
                        coordinate: userLocation ?? CLLocationCoordinate2D(),
                        distance: 0,
                        angle: 0,
                        manufacturerData: nil,
                        serviceUUIDs: nil,
                        isConnectable: true,
                        txPowerLevel: nil,
                        advertisementData: nil,
                        state: peripheral.state,
                        services: nil,
                        characteristics: nil,
                        lastSeen: Date(),
                        firstSeen: Date(),
                        deviceType: nil,
                        batteryLevel: nil,
                        discoveryHistory: [(timestamp: Date(), rssi: 0)]
                    )
                    deviceMap[deviceId] = tempDevice
                }
                
                // Update connection state
                connectionStates[deviceId] = .connecting
                
                // Attempt connection with saved settings
                manager.connect(peripheral, options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnNotificationKey: true,
                    CBConnectPeripheralOptionStartDelayKey: 0
                ])
                
                // Store in connected peripherals
                connectedPeripherals[deviceId] = peripheral
                
                logger.info("🔌 Auto-reconnect initiated for device: \(deviceId)")
            } else {
                logger.warning("⚠️ Could not retrieve peripheral \(deviceId) for auto-reconnect")
            }
        }
    }

    func updateFilteredDevices() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let newFilteredDevices = self.deviceMap.values.filter { device in
                switch self.selectedRSSIFilter {
                case .all:
                    return true
                case .strongSignal:
                    return device.rssi.intValue > -50
                case .mediumSignal:
                    return device.rssi.intValue >= -80 && device.rssi.intValue <= -50
                case .weakSignal:
                    return device.rssi.intValue < -80
                }
            }.filter { device in
                self.searchText.isEmpty || device.name.localizedCaseInsensitiveContains(self.searchText)
            }
            
            if newFilteredDevices != self.filteredDevices {
                self.filteredDevices = newFilteredDevices
                self.totalFilteredDevices = self.filteredDevices.count
                self.updateDeviceLocations()
            }
        }
    }

    func updateRegion() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let latitudes = self.deviceLocations.map { $0.coordinate.latitude }
            let longitudes = self.deviceLocations.map { $0.coordinate.longitude }
            
            let maxLat = latitudes.max() ?? 37.7749
            let minLat = latitudes.min() ?? 37.7749
            let maxLong = longitudes.max() ?? -122.4194
            let minLong = longitudes.min() ?? -122.4194
            
            let span = MKCoordinateSpan(
                latitudeDelta: (maxLat - minLat) * 1.5,
                longitudeDelta: (maxLong - minLong) * 1.5
            )
            
            let center = CLLocationCoordinate2D(
                latitude: (maxLat + minLat) / 2,
                longitude: (maxLong + minLong) / 2
            )
            
            self.region = MKCoordinateRegion(center: center, span: span)
        }
    }

    func isDeviceWithinRange(device: BluetoothDevice) -> Bool {
        return device.rssi.intValue > -50
    }

    private func updateDeviceLocations() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.deviceLocations = self.deviceMap.values.map { device in
                DeviceLocation(
                    name: device.name,
                    coordinate: device.coordinate
                )
            }
        }
    }

    // Connection Management Functions
    func connectToDevice(device: BluetoothDevice, settings: ConnectionSettings? = nil) {
        logger.info("🔌 Attempting to connect to device: \(device.name)")
        
        // First try to get the peripheral from discovered peripherals
        guard let peripheral = discoveredPeripherals[device.id] else {
            logger.error("❌ Could not find device in discovered peripherals, trying to retrieve...")
            
            // Try to retrieve the peripheral
            if let retrievedPeripheral = centralManager?.retrievePeripherals(withIdentifiers: [device.id]).first {
                logger.info("✅ Successfully retrieved peripheral")
                discoveredPeripherals[device.id] = retrievedPeripheral
                // Recursively call connect with the retrieved peripheral
                connectToDevice(device: device, settings: settings)
                return
            } else {
                logger.error("❌ Failed to retrieve peripheral - device not found")
                return
            }
        }
        
        // Check if already connected
        if peripheral.state == .connected {
            logger.info("✅ Device is already connected: \(device.name)")
            return
        }
        
        // Ensure delegate is set
        peripheral.delegate = self
        
        // Store in connected peripherals
        connectedPeripherals[device.id] = peripheral
        
        // Save or update settings
        if let settings = settings {
            connectionSettings[device.id] = settings
        }
        
        // Update connection state
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connectionStates[device.id] = .connecting
            
            // Verify device is in map
            if let existingDevice = self.deviceMap[device.id] {
                logger.info("✅ Device found in map: \(existingDevice.name)")
            } else {
                logger.warning("⚠️ Device not found in map, recreating...")
                // Recreate device entry if missing
                let newDevice = BluetoothDevice(
                    id: device.id,
                    name: device.name,
                    rssi: device.rssi,
                    count: 1,
                    coordinate: device.coordinate,
                    distance: device.distance,
                    angle: device.angle,
                    manufacturerData: device.manufacturerData,
                    serviceUUIDs: device.serviceUUIDs,
                    isConnectable: true,
                    txPowerLevel: device.txPowerLevel,
                    advertisementData: device.advertisementData,
                    state: peripheral.state,
                    services: nil,
                    characteristics: nil,
                    lastSeen: Date(),
                    firstSeen: Date(),
                    deviceType: device.deviceType,
                    batteryLevel: device.batteryLevel,
                    discoveryHistory: [(timestamp: Date(), rssi: device.rssi.intValue)]
                )
                self.deviceMap[device.id] = newDevice
                logger.info("✅ Device recreated in map")
            }
        }
        
        // Connect with all available options
        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true,
            CBConnectPeripheralOptionStartDelayKey: 0
        ]
        
        logger.info("🔌 Initiating connection to: \(peripheral.name ?? peripheral.identifier.uuidString)")
        
        // Attempt connection
        centralManager?.connect(peripheral, options: options)
        
        // Set connection timeout
        let timeoutDuration: TimeInterval = settings?.timeoutDuration ?? 10.0
        let timer = Timer.scheduledTimer(withTimeInterval: timeoutDuration, repeats: false) { [weak self] _ in
            self?.handleConnectionTimeout(for: device.id)
        }
        pendingConnections[device.id] = timer
    }
    
    private func handleConnectionTimeout(for deviceId: UUID) {
        logger.warning("⚠️ Connection timeout for device: \(deviceId)")
        
        // Cancel any pending connection
        if let peripheral = connectedPeripherals[deviceId] {
            centralManager?.cancelPeripheralConnection(peripheral)
            logger.info("🔌 Cancelled pending connection")
        }
        
        // Clean up
        pendingConnections[deviceId]?.invalidate()
        pendingConnections.removeValue(forKey: deviceId)
        connectedPeripherals.removeValue(forKey: deviceId)
        
        DispatchQueue.main.async {
            self.connectionStates[deviceId] = .disconnected
            logger.info("🔄 Reset connection state to disconnected")
        }
    }
    
    func disconnectDevice(device: BluetoothDevice) {
        guard let peripheral = connectedPeripherals[device.id] ?? discoveredPeripherals[device.id] else {
            logger.warning("⚠️ Cannot disconnect: Device not found in connected peripherals")
            return
        }
        
        logger.info("🔌 Disconnecting from device: \(device.name)")
        
        // Update state before disconnecting
        DispatchQueue.main.async {
            self.connectionStates[device.id] = .disconnecting
        }
        
        // Cancel any pending timeouts
        pendingConnections[device.id]?.invalidate()
        pendingConnections.removeValue(forKey: device.id)
        
        // Disconnect
        centralManager?.cancelPeripheralConnection(peripheral)
        
        // Clean up
        connectedPeripherals.removeValue(forKey: device.id)
    }
    
    // MARK: - Characteristic Operations
    
    func readCharacteristic(_ characteristic: CBCharacteristic) {
        guard let service = characteristic.service,
              let peripheral = service.peripheral,
              let deviceId = peripheral.identifier as UUID?,
              connectedPeripherals[deviceId] != nil else {
            logger.error("❌ Cannot read characteristic: peripheral not found")
            return
        }
        
        logger.info("📖 Reading characteristic: \(characteristic.uuid)")
        peripheral.readValue(for: characteristic)
    }
    
    func writeCharacteristic(_ characteristic: CBCharacteristic, data: Data) {
        guard let service = characteristic.service,
              let peripheral = service.peripheral,
              let deviceId = peripheral.identifier as UUID?,
              connectedPeripherals[deviceId] != nil else {
            logger.error("❌ Cannot write characteristic: peripheral not found")
            return
        }
        
        logger.info("✏️ Writing to characteristic: \(characteristic.uuid)")
        writeRequests[characteristic.uuid] = data
        
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
    }
    
    func toggleNotifications(for characteristic: CBCharacteristic) {
        guard let service = characteristic.service,
              let peripheral = service.peripheral,
              let deviceId = peripheral.identifier as UUID?,
              connectedPeripherals[deviceId] != nil else {
            logger.error("❌ Cannot toggle notifications: peripheral not found")
            return
        }
        
        let enable = !notifyingCharacteristics.contains(characteristic.uuid)
        logger.info("\(enable ? "🔔" : "🔕") \(enable ? "Enabling" : "Disabling") notifications for: \(characteristic.uuid)")
        
        peripheral.setNotifyValue(enable, for: characteristic)
    }
    
    // MARK: - Connection Settings
    
    public func updateConnectionSettings(for deviceId: UUID, settings: ConnectionSettings) {
        connectionSettings[deviceId] = settings
        
        // Apply settings if device is connected
        if let peripheral = connectedPeripherals[deviceId] {
            applyConnectionSettings(peripheral: peripheral, settings: settings)
        }
        
        // Save settings to persistent storage
        saveConnectionSettings()
        logger.info("✅ Updated and saved connection settings for device: \(deviceId)")
    }
    
    private func saveConnectionSettings() {
        do {
            let data = try JSONEncoder().encode(connectionSettings)
            UserDefaults.standard.set(data, forKey: "ConnectionSettings")
            logger.info("✅ Connection settings saved successfully")
        } catch {
            logger.error("❌ Failed to save connection settings: \(error.localizedDescription)")
        }
    }

    
    private func loadConnectionSettings() {
        guard let data = UserDefaults.standard.data(forKey: "ConnectionSettings") else {
            logger.info("ℹ️ No saved connection settings found")
            return
        }
        
        do {
            let settings = try JSONDecoder().decode([UUID: ConnectionSettings].self, from: data)
            connectionSettings = settings
            logger.info("✅ Connection settings loaded successfully")
        } catch {
            logger.error("❌ Failed to load connection settings: \(error.localizedDescription)")
        }
    }
    
    private func applyConnectionSettings(peripheral: CBPeripheral, settings: ConnectionSettings) {
        // Set connection priority
        var connectionParams: [String: Any] = [:]
        switch settings.connectionPriority {
        case .high:
            connectionParams[CBConnectPeripheralOptionStartDelayKey] = 0
        case .balanced:
            break // Use default settings
        case .low:
            break // Note: Low power settings are handled through connection interval
        }
        
        // Note: MTU and PHY settings are not directly configurable in iOS
        // The system will automatically negotiate these parameters
        logger.info("✅ Applied connection settings to peripheral: \(peripheral.identifier)")
    }
    
    // MARK: - Auto-reconnect
    
    // Remove the old handleAutoReconnect function since we're now handling it directly in didDisconnectPeripheral
    // private func handleAutoReconnect(for deviceId: UUID) { ... }
    
    // MARK: - CBCentralManagerDelegate Connection Methods
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier
        logger.info("✅ Connected to device: \(peripheral.name ?? deviceId.uuidString)")
        
        // Clear timeout timer
        pendingConnections[deviceId]?.invalidate()
        pendingConnections.removeValue(forKey: deviceId)
        
        // Store connected peripheral and ensure delegate is set
        peripheral.delegate = self
        connectedPeripherals[deviceId] = peripheral
        
        DispatchQueue.main.async {
            self.connectionStates[deviceId] = .connected
            logger.info("🔄 Connection state updated to connected")
        }
        
        // Start discovering services - pass nil to discover all services
        logger.info("🔍 Starting service discovery for all services...")
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier
        if let error = error {
            logger.error("❌ Failed to connect to device: \(error.localizedDescription)")
        } else {
            logger.error("❌ Failed to connect to device: unknown error")
        }
        
        // Clean up
        pendingConnections[deviceId]?.invalidate()
        pendingConnections.removeValue(forKey: deviceId)
        connectedPeripherals.removeValue(forKey: deviceId)
        
        DispatchQueue.main.async {
            self.connectionStates[deviceId] = .disconnected
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier
        
        if let error = error {
            logger.error("❌ Device disconnected with error: \(error.localizedDescription)")
            
            // Check if auto-reconnect is enabled for this device
            if let settings = connectionSettings[deviceId], settings.autoReconnect {
                logger.info("🔄 Auto-reconnect is enabled, attempting to reconnect...")
                
                // Update state to show reconnecting
                DispatchQueue.main.async {
                    self.connectionStates[deviceId] = .connecting
                }
                
                // Attempt reconnection with saved settings
                guard let manager = centralManager else {
                    logger.error("❌ Cannot reconnect: Bluetooth manager is not available")
                    cleanupDisconnectedDevice(deviceId: deviceId)
                    return
                }
                
                manager.connect(peripheral, options: [
                    CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                    CBConnectPeripheralOptionNotifyOnNotificationKey: true,
                    CBConnectPeripheralOptionStartDelayKey: 0
                ])
                
                // Keep the peripheral in connected peripherals to maintain the connection attempt
                connectedPeripherals[deviceId] = peripheral
                
                logger.info("🔌 Auto-reconnect initiated for device: \(peripheral.name ?? deviceId.uuidString)")
            } else {
                logger.info("ℹ️ Auto-reconnect is disabled for this device")
                cleanupDisconnectedDevice(deviceId: deviceId)
            }
        } else {
            logger.info("🔌 Device disconnected normally")
            cleanupDisconnectedDevice(deviceId: deviceId)
        }
    }
    
    private func cleanupDisconnectedDevice(deviceId: UUID) {
        // Remove from connected peripherals
        connectedPeripherals.removeValue(forKey: deviceId)
        
        // Update connection state
        DispatchQueue.main.async {
            self.connectionStates[deviceId] = .disconnected
        }
        
        logger.info("✅ Cleaned up disconnected device: \(deviceId)")
    }
    
    // MARK: - CBPeripheralDelegate Value Updates
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("❌ Characteristic update failed: \(error.localizedDescription)")
            return
        }
        
        let deviceId = peripheral.identifier
        
        // Update characteristic value
        if let value = characteristic.value {
            DispatchQueue.main.async {
                self.characteristicValues[characteristic.uuid] = value
            }
        }
        
        // Handle specific characteristics
        if characteristic.uuid == CBUUID(string: "2A19") { // Battery Level
            handleBatteryLevelUpdate(deviceId: deviceId, characteristic: characteristic)
        }
    }
    
    private func handleBatteryLevelUpdate(deviceId: UUID, characteristic: CBCharacteristic) {
        guard let data = characteristic.value,
              data.count > 0 else {
            return
        }
        
        let batteryLevel = Int(data[0])
        if var device = deviceMap[deviceId] {
            device.batteryLevel = batteryLevel
            DispatchQueue.main.async {
                self.deviceMap[deviceId] = device
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writeRequests.removeValue(forKey: characteristic.uuid)
        
        if let error = error {
            logger.error("❌ Write failed for characteristic \(characteristic.uuid): \(error.localizedDescription)")
        } else {
            logger.info("✅ Write successful for characteristic: \(characteristic.uuid)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("❌ Notification state update failed: \(error.localizedDescription)")
            return
        }
        
        DispatchQueue.main.async {
            if characteristic.isNotifying {
                self.notifyingCharacteristics.insert(characteristic.uuid)
            } else {
                self.notifyingCharacteristics.remove(characteristic.uuid)
            }
        }
    }

    // MARK: - CBPeripheralDelegate Service Discovery
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let deviceId = peripheral.identifier
        
        if let error = error {
            logger.error("❌ Service discovery failed: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            logger.warning("⚠️ No services found")
            return
        }
        
        logger.info("📡 Found \(services.count) services")
        
        // Update device with discovered services
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if var device = self.deviceMap[deviceId] {
                device.services = services
                self.deviceMap[deviceId] = device
                self.objectWillChange.send()
                
                // Log and discover characteristics for each service
                for service in services {
                    let serviceInfo = self.getServiceInfo(service)
                    logger.info("📡 Service: \(serviceInfo.name) (\(service.uuid.uuidString))")
                    
                    // Discover characteristics for this service
                    peripheral.discoverCharacteristics(nil, for: service)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            logger.error("❌ Characteristic discovery failed: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            logger.warning("⚠️ No characteristics found for service: \(service.uuid)")
            return
        }
        
        logger.info("📡 Discovered \(characteristics.count) characteristics for service: \(service.uuid)")
        
        // Update device with discovered characteristics
        let deviceId = peripheral.identifier
        logger.info("🔍 Attempting to update device \(deviceId) with characteristics")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if var device = self.deviceMap[deviceId] {
                logger.info("✅ Found device in map, updating characteristics")
                device.characteristics = (device.characteristics ?? []) + characteristics
                self.deviceMap[deviceId] = device
                self.objectWillChange.send()
                logger.info("✅ Device map and UI updated with characteristics")
                
                // Log the current state of the device
                logger.info("📱 Device state after update - Services: \(device.services?.count ?? 0), Characteristics: \(device.characteristics?.count ?? 0)")
            } else {
                logger.error("❌ Device \(deviceId) not found in device map for characteristic update")
            }
            
            // Look for interesting characteristics (e.g., battery level)
            for characteristic in characteristics {
                if characteristic.uuid == CBUUID(string: "2A19") { // Battery Level
                    logger.info("🔋 Found battery level characteristic, reading value...")
                    peripheral.readValue(for: characteristic)
                }
            }
        }
    }
}

extension Data {
    var hexDescription: String {
        return self.map { String(format: "%02X", $0) }.joined()
    }
}

extension ProcessInfo.ThermalState {
    var description: String {
        switch self {
        case .nominal:
            return "Normal"
        case .fair:
            return "Fair"
        case .serious:
            return "Serious"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }
    
    var color: Color {
        switch self {
        case .nominal:
            return .green
        case .fair:
            return .yellow
        case .serious:
            return .orange
        case .critical:
            return .red
        @unknown default:
            return .gray
        }
    }
}


