//
//  HapticManager.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 12/11/24.
//


import Foundation
import UIKit
import os.log

class HapticManager {
    static let shared = HapticManager()
    
    private init() {
        logger.info("🔄 Haptic manager initialized")
    }
    
    func triggerHapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        logger.debug("🔄 Haptic feedback triggered with style: \(style.rawValue)")
    }
    
    func triggerNotificationFeedback(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
        logger.debug("🔔 Notification feedback triggered with type: \(type.rawValue)")
    }
    
    func triggerSelectionFeedback() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        logger.debug("🔄 Selection feedback triggered")
    }
}
