//
//  ContentView.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 8/8/24.
//

import SwiftUI

struct BluetoothTrackerView: View {
    @ObservedObject private var viewModel = BluetoothViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Total Devices Found: \(viewModel.totalFilteredDevices)")
                    .font(.headline)
                    .padding(.top)
                
                if viewModel.filteredDevices.isEmpty {
                    Text("No devices found")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List {
                        ForEach(viewModel.filteredDevices) { device in
                            HStack {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name)
                                        .font(.body)
                                        .bold()
                                    
                                    HStack {
                                        Text("RSSI: \(device.rssi)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        
                                        Spacer()
                                        
                                        Text("Seen: \(device.count) times")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $viewModel.searchText)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        viewModel.startScan()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    FilterToolbarView(selectedRSSIFilter: $viewModel.selectedRSSIFilter)
                }
            }
            .onChange(of: viewModel.searchText) { viewModel.updateFilteredDevices()
            }
            .onChange(of: viewModel.selectedRSSIFilter) { viewModel.updateFilteredDevices()
            }
        }
    }
}


#Preview {
    BluetoothTrackerView()
}

struct FilterToolbarView: View {
    @Binding var selectedRSSIFilter: BluetoothViewModel.RSSIFilter
    
    var body: some View {
        Picker("Filter", selection: $selectedRSSIFilter) {
            ForEach(BluetoothViewModel.RSSIFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(MenuPickerStyle())
        .fixedSize()
    }
}
