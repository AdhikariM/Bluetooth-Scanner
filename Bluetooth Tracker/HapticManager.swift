//
//  HapticManager.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 12/11/24.
//


import Foundation
import SwiftUI

class HapticManager {
   static  let generator = UINotificationFeedbackGenerator()
    
    static func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        generator.notificationOccurred(type)
    }
}
