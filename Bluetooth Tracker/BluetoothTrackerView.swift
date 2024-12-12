//
//  ContentView.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 8/8/24.
//

import MapKit
import SwiftUI

struct BluetoothTrackerView: View {
    @ObservedObject private var viewModel = BluetoothViewModel()
    @StateObject private var locationManager = LocationManager()
    @State private var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 4) {

                    if let currentLocation = locationManager.currentLocation {
                        Map(position: $mapPosition) {
                            Marker(UIDevice.current.name, coordinate: currentLocation)
                        }
                        .mapControls {
                           MapUserLocationButton()
                           MapScaleView()
                        }
                        .frame(height: 200)
                        .cornerRadius(12)
                        .padding()
                        .onAppear {
                            setMapToCurrentLocation()
                        }
                    } else {
                        Text("Retrieving current location...")
                            .foregroundColor(.gray)
                            .padding()
                    }

                    Text("Total Devices Found: \(viewModel.totalFilteredDevices)")
                        .font(.headline)
                        .padding(.horizontal)

                    if viewModel.filteredDevices.isEmpty {
                        Text("No devices found")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        VStack {
                            ForEach(viewModel.filteredDevices) { device in
                                HStack {
                                    DeviceRowView(device: device)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .padding()
                                .background {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(uiColor: .systemGray4).opacity(0.4))
                                }
                            }
                        }
                        .padding(.horizontal)
                        .searchable(text: $viewModel.searchText)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        withAnimation(.linear(duration: 2.0)) {
                            setMapToCurrentLocation()
                            viewModel.startScan()
                        }
                    }, label: {
                        Image(systemName: "arrow.trianglehead.clockwise")
                    })
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    FilterToolbarView(selectedRSSIFilter: $viewModel.selectedRSSIFilter)
                }
            }
            .onChange(of: viewModel.searchText) { viewModel.updateFilteredDevices() }
            .onChange(of: viewModel.selectedRSSIFilter) { viewModel.updateFilteredDevices() }
        }
    }
    
    private func setMapToCurrentLocation() {
        if let currentLocation = locationManager.currentLocation {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: currentLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
    }
}

struct DeviceRowView: View {
    var device: BluetoothDevice

    var body: some View {
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
        .padding(.vertical, 8)
    }
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

#Preview {
    BluetoothTrackerView()
}
