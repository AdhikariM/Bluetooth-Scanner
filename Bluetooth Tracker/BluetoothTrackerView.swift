//
//  ContentView.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 8/8/24.
//

import MapKit
import SwiftUI
import CoreBluetooth


struct BluetoothTrackerView: View {
    @StateObject private var viewModel = BluetoothViewModel()
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
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search devices", text: $viewModel.searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        if !viewModel.searchText.isEmpty {
                            Button(action: {
                                viewModel.searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
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
                        VStack(spacing: 8) {
                            ForEach(viewModel.filteredDevices) { device in
                                DeviceRowView(device: device)
                                    .padding(.horizontal)
                                    .background {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(uiColor: .systemGray4).opacity(0.4))
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Bluetooth Tracker").toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.startScan(triggerHaptic: true)
                        setMapToCurrentLocation()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
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
    @State private var showingDetail = false
    
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
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            showingDetail = true
        }
        .sheet(isPresented: $showingDetail) {
            DeviceDetailView(device: device)
        }
    }
}

struct DeviceDetailView: View {
    let device: BluetoothDevice
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Enhanced Signal Indicator
                    SignalIndicatorView(device: device)
                        .frame(height: 200)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(15)
                        .shadow(radius: 5)
                    
                    // Device Info Section
                    VStack(spacing: 15) {
                        DetailRow(title: "Name", value: device.name)
                        DetailRow(title: "Type", value: device.deviceType ?? "Unknown")
                        DetailRow(title: "Signal Quality", value: device.signalQuality)
                        DetailRow(title: "Distance", value: String(format: "%.1f m", device.distance))
                        DetailRow(title: "Angle", value: String(format: "%.1f°", device.angle))
                        DetailRow(title: "RSSI", value: "\(device.rssi) dBm")
                        DetailRow(title: "Times Seen", value: "\(device.count)")
                        DetailRow(title: "First Seen", value: device.firstSeen.formatted())
                        DetailRow(title: "Last Seen", value: device.lastSeen.formatted())
                        if let batteryLevel = device.batteryLevel {
                            DetailRow(title: "Battery", value: "\(batteryLevel)%")
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(15)
                    .shadow(radius: 5)
                    
                    NavigationLink(destination: SignalHistoryGraphView(device: device)) {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.title2)
                            Text("View Signal History")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Device Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SignalIndicatorView: View {
    let device: BluetoothDevice
    @State private var rotation: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                    
                    Circle()
                        .trim(from: 0, to: signalStrengthFraction)
                        .stroke(signalStrengthColor, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    
                    Image(systemName: "arrow.up")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(device.angle))
                        .shadow(radius: 2)
                }
                .frame(width: geometry.size.width * 0.6)
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Distance")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f m", device.distance))
                            .font(.title2)
                            .bold()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Signal")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(device.signalQuality)
                            .font(.headline)
                            .foregroundColor(signalStrengthColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RSSI")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(device.rssi) dBm")
                            .font(.headline)
                    }
                }
                .frame(width: geometry.size.width * 0.4)
                .padding(.leading)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
    
    private var signalStrengthFraction: Double {
        let rssi = device.rssi.doubleValue
        let minRSSI = -100.0
        let maxRSSI = 0.0
        return (rssi - minRSSI) / (maxRSSI - minRSSI)
    }
    
    private var signalStrengthColor: Color {
        switch device.signalQuality {
        case "Excellent":
            return .green
        case "Very Good":
            return .blue
        case "Good":
            return .yellow
        case "Fair":
            return .orange
        default:
            return .red
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.subheadline)
                .bold()
        }
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

struct DeviceLocation: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct MapView: View {
    let devices: [DeviceLocation]
    @Environment(\.dismiss) private var dismiss
    @State private var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )
    
    var body: some View {
        NavigationStack {
            Map(position: $mapPosition) {
                ForEach(devices) { device in
                    Marker(device.name, coordinate: device.coordinate)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapScaleView()
            }
            .navigationTitle("Device Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    BluetoothTrackerView()
}
