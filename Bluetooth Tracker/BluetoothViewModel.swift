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

class BluetoothViewModel: NSObject, ObservableObject, CBCentralManagerDelegate, CLLocationManagerDelegate {
    @Published var deviceMap = [UUID: BluetoothDevice]()
    @Published var searchText = ""
    @Published var selectedRSSIFilter = RSSIFilter.all
    @Published private(set) var filteredDevices: [BluetoothDevice] = []
    @Published private(set) var totalFilteredDevices: Int = 0
    @Published var deviceLocations: [DeviceLocation] = []
    @Published var region: MKCoordinateRegion
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var selectedDevice: BluetoothDevice?
    
    private var centralManager: CBCentralManager?
    private var locationManager: CLLocationManager?
    private let orientationManager = OrientationManager()
    private var updateTimer: Timer?
    private var lastUpdateTime: Date = Date()
    private let minimumUpdateInterval: TimeInterval = 1.0
    private var isScanning = false
    private var lastRSSIUpdate: [UUID: NSNumber] = [:]
    private let rssiThreshold: Int = 5
    private let scanQueue = DispatchQueue(label: "com.bluetooth.scan", qos: .userInitiated)
    private var deviceUpdateQueue = DispatchQueue(label: "com.bluetooth.deviceUpdate", qos: .userInitiated)

    enum RSSIFilter: String, CaseIterable, Identifiable {
        case all = "RSSI: All"
        case strongSignal = "Strong (> -50)"
        case mediumSignal = "Medium (-50 to -80)"
        case weakSignal = "Weak (< -80)"
        
        var id: String { self.rawValue }
    }

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
        
        centralManager = CBCentralManager(delegate: self, queue: scanQueue)
        
        startContinuousUpdates()
    }

    private func startContinuousUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDeviceAnglesAndDistances()
        }
        RunLoop.main.add(updateTimer!, forMode: .common)
    }
    
    deinit {
        updateTimer?.invalidate()
        updateTimer = nil
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
        print("Failed to get user location: \(error.localizedDescription)")
    }

    func startScan(triggerHaptic: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard !self.isScanning else { return }
            self.isScanning = true
            
            self.deviceMap.removeAll()
            self.lastRSSIUpdate.removeAll()
            self.centralManager?.stopScan()
            
            let options: [String: Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ]
            
            self.centralManager?.scanForPeripherals(withServices: nil, options: options)
            self.updateFilteredDevices()
            
            if triggerHaptic {
                HapticManager.notification(type: .success)
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
        let currentTime = Date()
        
        deviceUpdateQueue.async { [weak self] in
            guard let self = self else { return }
            
            let deviceId = peripheral.identifier
            let lastRSSI = self.lastRSSIUpdate[deviceId]
            
            if let lastRSSI = lastRSSI, abs(lastRSSI.intValue - RSSI.intValue) <= self.rssiThreshold {
                return
            }
            
            self.lastRSSIUpdate[deviceId] = RSSI
            
            let deviceName = peripheral.name ?? deviceId.uuidString
            let distance = self.calculateDistance(from: RSSI)
            let angle = self.orientationManager.calculateAngleToDevice(deviceRSSI: RSSI)
            let deviceLocation = CLLocationCoordinate2D(latitude: 90.00, longitude: 90.00)
            
            let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
            let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
            let isConnectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? false
            let txPowerLevel = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber
            
            let deviceType = self.determineDeviceType(serviceUUIDs: serviceUUIDs, manufacturerData: manufacturerData)
            
            let newDevice: BluetoothDevice
            
            if let existingDevice = self.deviceMap[deviceId] {
                var history = existingDevice.discoveryHistory
                history.append((timestamp: currentTime, rssi: RSSI.intValue))
                
                let thirtyMinutesAgo = currentTime.addingTimeInterval(-30 * 60)
                history = history.filter { $0.timestamp >= thirtyMinutesAgo }
                
                newDevice = BluetoothDevice(
                    id: deviceId,
                    name: existingDevice.name,
                    rssi: RSSI,
                    count: existingDevice.count + 1,
                    coordinate: deviceLocation,
                    distance: distance,
                    angle: angle,
                    manufacturerData: manufacturerData,
                    serviceUUIDs: serviceUUIDs,
                    isConnectable: isConnectable,
                    txPowerLevel: txPowerLevel,
                    advertisementData: advertisementData,
                    state: peripheral.state,
                    services: existingDevice.services,
                    characteristics: existingDevice.characteristics,
                    lastSeen: currentTime,
                    firstSeen: existingDevice.firstSeen,
                    deviceType: deviceType,
                    batteryLevel: existingDevice.batteryLevel,
                    discoveryHistory: history
                )
            } else {
                newDevice = BluetoothDevice(
                    id: deviceId,
                    name: deviceName,
                    rssi: RSSI,
                    count: 1,
                    coordinate: deviceLocation,
                    distance: distance,
                    angle: angle,
                    manufacturerData: manufacturerData,
                    serviceUUIDs: serviceUUIDs,
                    isConnectable: isConnectable,
                    txPowerLevel: txPowerLevel,
                    advertisementData: advertisementData,
                    state: peripheral.state,
                    services: nil,
                    characteristics: nil,
                    lastSeen: currentTime,
                    firstSeen: currentTime,
                    deviceType: deviceType,
                    batteryLevel: nil,
                    discoveryHistory: [(timestamp: currentTime, rssi: RSSI.intValue)]
                )
            }
            
            DispatchQueue.main.async {
                self.deviceMap[deviceId] = newDevice
                self.lastUpdateTime = currentTime
                self.updateFilteredDevices()
            }
        }
        
        updateDeviceLocations()
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
            if central.state == .poweredOn {
                self.startScan(triggerHaptic: false)
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
}

extension Data {
    var hexDescription: String {
        return self.map { String(format: "%02X", $0) }.joined()
    }
}
