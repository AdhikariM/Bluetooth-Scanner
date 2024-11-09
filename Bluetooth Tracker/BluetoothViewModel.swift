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

struct BluetoothDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: NSNumber
    let count: Int
    let coordinate: CLLocationCoordinate2D
}

class BluetoothViewModel: NSObject, ObservableObject, CBCentralManagerDelegate, CLLocationManagerDelegate {
    @Published var deviceMap = [UUID: BluetoothDevice]()
    @Published var searchText = ""
    @Published var selectedRSSIFilter = RSSIFilter.all
    @Published private(set) var filteredDevices: [BluetoothDevice] = []
    @Published private(set) var totalFilteredDevices: Int = 0
    @Published var deviceLocations: [BluetoothDevice] = []
    @Published var region: MKCoordinateRegion
    @Published var userLocation: CLLocationCoordinate2D?

    private var centralManager: CBCentralManager?
    private var locationManager: CLLocationManager?

    enum RSSIFilter: String, CaseIterable, Identifiable {
        case all = "RSSI: All"
        case strongSignal = "Strong (> -50)"
        case mediumSignal = "Medium (-50 to -80)"
        case weakSignal = "Weak (< -80)"
        
        var id: String { self.rawValue }
    }

    override init() {
        self.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to San Francisco
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        super.init()
        
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.requestWhenInUseAuthorization()
        locationManager?.startUpdatingLocation()
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // CLLocationManagerDelegate method
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            userLocation = location.coordinate
            updateRegion()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get user location: \(error.localizedDescription)")
    }

    func startScan() {
        deviceMap.removeAll()
        centralManager?.stopScan()
        centralManager?.scanForPeripherals(withServices: nil, options: nil)
        updateFilteredDevices()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceId = peripheral.identifier
        let deviceName = peripheral.name ?? deviceId.uuidString

        let deviceLocation = CLLocationCoordinate2D(latitude: 90.00, longitude: 90.00)

        if let existingDevice = deviceMap[deviceId] {
            deviceMap[deviceId] = BluetoothDevice(id: deviceId, name: existingDevice.name, rssi: RSSI, count: existingDevice.count + 1, coordinate: deviceLocation)
        } else {
            deviceMap[deviceId] = BluetoothDevice(id: deviceId, name: deviceName, rssi: RSSI, count: 1, coordinate: deviceLocation)
        }

        updateFilteredDevices()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScan()
        }
    }

    func updateFilteredDevices() {
        filteredDevices = deviceMap.values.filter { device in
            switch selectedRSSIFilter {
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
            searchText.isEmpty || device.name.localizedCaseInsensitiveContains(searchText)
        }
        
        totalFilteredDevices = filteredDevices.count
        deviceLocations = filteredDevices
    }

    func updateRegion() {
        guard let userLocation = userLocation else { return }
        
        let latitudes = deviceLocations.map { $0.coordinate.latitude }
        let longitudes = deviceLocations.map { $0.coordinate.longitude }
        
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
        
        region = MKCoordinateRegion(center: center, span: span)
    }

    func isDeviceWithinRange(device: BluetoothDevice) -> Bool {
        return device.rssi.intValue > -50
    }
}
