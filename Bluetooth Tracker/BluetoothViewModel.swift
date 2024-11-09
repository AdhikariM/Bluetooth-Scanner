//
//  BluetoothViewModel.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 8/8/24.
//

import Foundation
import CoreBluetooth
import Combine

struct BluetoothDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: NSNumber
    let count: Int
}

class BluetoothViewModel: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var deviceMap = [UUID: BluetoothDevice]()
    @Published var searchText = ""
    @Published var selectedRSSIFilter = RSSIFilter.all
    @Published private(set) var filteredDevices: [BluetoothDevice] = []
    @Published private(set) var totalFilteredDevices: Int = 0

    private var centralManager: CBCentralManager?

    enum RSSIFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case strongSignal = "Strong (> -50)"
        case mediumSignal = "Medium (-50 to -80)"
        case weakSignal = "Weak (< -80)"
        
        var id: String { self.rawValue }
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        updateFilteredDevices()
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
        
        if let existingDevice = deviceMap[deviceId] {
            deviceMap[deviceId] = BluetoothDevice(id: deviceId, name: existingDevice.name, rssi: RSSI, count: existingDevice.count + 1)
        } else {
            deviceMap[deviceId] = BluetoothDevice(id: deviceId, name: deviceName, rssi: RSSI, count: 1)
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
    }
}
