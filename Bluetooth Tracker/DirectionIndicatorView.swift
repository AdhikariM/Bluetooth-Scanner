//
//  DirectionIndicatorView.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 3/31/25.
//

import SwiftUI

struct DirectionIndicatorView: View {
    let angle: Double
    let distance: Double
    let deviceName: String
    
    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                    .frame(width: 200, height: 200)
                
                Image(systemName: "arrow.up")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                    .rotationEffect(.degrees(angle))
                    .animation(.linear(duration: 0.1), value: angle)
                
                Text(String(format: "%.1f m", distance))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .offset(y: 100)
            }
            
            Text(deviceName)
                .font(.headline)
                .padding(.top)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(uiColor: .systemBackground))
                .shadow(radius: 5)
        )
    }
}
