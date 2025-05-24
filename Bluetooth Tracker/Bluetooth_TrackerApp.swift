//
//  Bluetooth_TrackerApp.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 8/8/24.
//

import SwiftUI
import os.log

@main
struct Bluetooth_TrackerApp: App {
    @StateObject private var bluetoothViewModel = BluetoothViewModel()
    
    init() {
        logger.info("🚀 App launched")
    }
    
    var body: some Scene {
        WindowGroup {
            BluetoothTrackerView()
                .environmentObject(bluetoothViewModel)
        }
    }
}
