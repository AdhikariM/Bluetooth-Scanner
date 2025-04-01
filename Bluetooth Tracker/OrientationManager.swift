//
//  OrientationManager.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 3/31/25.
//


import CoreMotion
import SwiftUI

class OrientationManager: NSObject, ObservableObject {
    @Published var heading: Double = 0
    @Published var deviceOrientation: UIDeviceOrientation = .unknown
    
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        setupMotionManager()
        setupLocationManager()
    }
    
    private func setupMotionManager() {
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let motion = motion else { return }
            
            // Get device orientation
            let orientation = UIDevice.current.orientation
            self?.deviceOrientation = orientation

            let attitude = motion.attitude
            var heading = attitude.yaw * 180 / .pi
            if heading < 0 {
                heading += 360
            }
            self?.heading = heading
        }
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.headingFilter = 5
        locationManager.startUpdatingHeading()
    }
    
    func calculateAngleToDevice(deviceRSSI: NSNumber) -> Double {
        // Convert RSSI to approximate distance (this is a rough estimation)
        let distance = pow(10, (deviceRSSI.doubleValue + 60) / 20)

        let angle = heading + (distance * 5)
        
        return angle
    }
}

extension OrientationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.trueHeading
    }
} 
