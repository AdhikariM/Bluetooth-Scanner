//
//  BluetoothViewModel.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 8/8/24.
//

import Foundation
import CoreBluetooth
import Combine

class BluetoothViewModel: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var names: [String] = []
    @Published var ids: [NSNumber] = []
    @Published var counts: [Int] = []
    @Published var totalDevices: Int = 0

    private var centralManager: CBCentralManager?
    private var deviceMap = [UUID: (name: String, rssi: NSNumber, count: Int)]()

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        deviceMap.removeAll() // Clear existing devices
        names = []
        ids = []
        counts = []
        totalDevices = 0
        centralManager?.stopScan()
        centralManager?.scanForPeripherals(withServices: nil, options: nil)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceId = peripheral.identifier
        let deviceName = peripheral.name ?? deviceId.uuidString

        if let existingDevice = deviceMap[deviceId] {
            deviceMap[deviceId] = (name: existingDevice.name, rssi: RSSI, count: existingDevice.count + 1)
        } else {
            deviceMap[deviceId] = (name: deviceName, rssi: RSSI, count: 1)
        }

        // Update the lists
        DispatchQueue.main.async {
            self.names = self.deviceMap.values.map { $0.name }
            self.ids = self.deviceMap.values.map { $0.rssi }
            self.counts = self.deviceMap.values.map { $0.count }
            self.totalDevices = self.deviceMap.count
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScan()
        } else {
            // Handle Bluetooth not available
            // Add appropriate user feedback if necessary
        }
    }
}
