//
//  LocationManager.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 11/9/24.
//


import CoreLocation
import Combine
import os.log

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocationCoordinate2D?
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        logger.info("📍 Location manager initialized")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            currentLocation = location.coordinate
            locationManager.stopUpdatingLocation()
            logger.debug("📍 Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            logger.info("✅ Location access authorized")
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            logger.error("❌ Location access denied or restricted")
        case .notDetermined:
            logger.info("⏳ Requesting location authorization")
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            logger.warning("⚠️ Unknown location authorization status")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("❌ Location manager error: \(error.localizedDescription)")
    }
}

