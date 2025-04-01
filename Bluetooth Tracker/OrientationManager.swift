//
//  OrientationManager.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 3/31/25.
//


import CoreMotion
import SwiftUI
import Foundation
import os.log

class OrientationManager: NSObject, ObservableObject {
    private let motionManager = CMMotionManager()
    @Published var currentHeading: Double = 0
    @Published var isUpdating = false
    
    override init() {
        super.init()
        logger.info("🧭 Orientation manager initialized")
        startUpdates()
    }
    
    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            logger.error("❌ Device motion not available")
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self else { return }
            
            if let error = error {
                logger.error("❌ Motion update error: \(error.localizedDescription)")
                return
            }
            
            guard let motion = motion else {
                logger.warning("⚠️ No motion data available")
                return
            }
            
            // Calculate heading from device motion
            let heading = motion.attitude.yaw * 180 / .pi
            self.currentHeading = heading
            self.isUpdating = true
        }
        
        logger.info("✅ Started motion updates")
    }
    
    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
        isUpdating = false
        logger.info("🛑 Stopped motion updates")
    }
    
    func calculateAngleToDevice(deviceRSSI: NSNumber) -> Double {
        // This is a simplified calculation - you might want to adjust based on your needs
        let baseAngle = currentHeading
        let rssiValue = deviceRSSI.doubleValue
        
        // Normalize RSSI to an angle (example: -100 to 0 dBm maps to 0 to 360 degrees)
        let normalizedRSSI = (rssiValue + 100) / 100
        let angleOffset = normalizedRSSI * 360
        
        return (baseAngle + angleOffset).truncatingRemainder(dividingBy: 360)
    }
    
    deinit {
        stopUpdates()
        logger.info("🧭 Orientation manager deinitialized")
    }
}

extension OrientationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        currentHeading = newHeading.trueHeading
    }
} 
