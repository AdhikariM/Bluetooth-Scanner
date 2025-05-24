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

struct ConnectionSettingsInlineView: View {
    let device: BluetoothDevice
    @EnvironmentObject private var viewModel: BluetoothViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            Toggle("Auto Reconnect", isOn: Binding(
                get: { viewModel.connectionSettings[device.id]?.autoReconnect ?? false },
                set: { newValue in
                    let currentSettings = viewModel.connectionSettings[device.id] ?? BluetoothViewModel.ConnectionSettings()
                    let newSettings = BluetoothViewModel.ConnectionSettings(
                        mtu: currentSettings.mtu,
                        connectionPriority: currentSettings.connectionPriority,
                        autoReconnect: newValue,
                        timeoutDuration: currentSettings.timeoutDuration
                    )
                    viewModel.updateConnectionSettings(for: device.id, settings: newSettings)
                }
            ))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Connection Priority")
                    .font(.subheadline)
                Picker("Priority", selection: Binding(
                    get: { viewModel.connectionSettings[device.id]?.connectionPriority ?? .balanced },
                    set: { newValue in
                        let currentSettings = viewModel.connectionSettings[device.id] ?? BluetoothViewModel.ConnectionSettings()
                        let newSettings = BluetoothViewModel.ConnectionSettings(
                            mtu: currentSettings.mtu,
                            connectionPriority: newValue,
                            autoReconnect: currentSettings.autoReconnect,
                            timeoutDuration: currentSettings.timeoutDuration
                        )
                        viewModel.updateConnectionSettings(for: device.id, settings: newSettings)
                    }
                )) {
                    Text("High").tag(BluetoothViewModel.ConnectionSettings.ConnectionPriority.high)
                    Text("Balanced").tag(BluetoothViewModel.ConnectionSettings.ConnectionPriority.balanced)
                    Text("Low Power").tag(BluetoothViewModel.ConnectionSettings.ConnectionPriority.low)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 8)
    }
}

struct DeviceDetailView: View {
    let device: BluetoothDevice
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: BluetoothViewModel
    
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
                    
                    // Connection Management Section
                    if device.isConnectable {
                        VStack {
                            connectionStateView
                            
                            if viewModel.connectionStates[device.id] == .connected {
                                VStack(spacing: 12) {
                                    Button(action: {
                                        viewModel.disconnectDevice(device: device)
                                    }) {
                                        Label("Disconnect", systemImage: "xmark.circle.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                    
                                    ConnectionSettingsInlineView(device: device)
                                }
                            } else if viewModel.connectionStates[device.id] != .connecting {
                                Button(action: {
                                    viewModel.connectToDevice(device: device)
                                }) {
                                    Label("Connect", systemImage: "plus.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.blue)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(15)
                        .shadow(radius: 5)
                        
                        // Show services when connected
                        if viewModel.connectionStates[device.id] == .connected {
                            ServicesSection(device: device)
                        }
                    }
                    
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
                //    .padding(.horizontal)
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
    
    private var connectionStateView: some View {
        HStack {
            Image(systemName: connectionStateIcon)
                .foregroundColor(connectionStateColor)
            Text(connectionStateText)
                .foregroundColor(connectionStateColor)
        }
        .font(.headline)
    }
    
    private var connectionStateIcon: String {
        switch viewModel.connectionStates[device.id] {
        case .connected:
            return "link.circle.fill"
        case .connecting:
            return "link.badge.plus"
        case .disconnecting:
            return "link.badge.minus"
        default:
            return "link.slash.circle"
        }
    }
    
    private var connectionStateColor: Color {
        switch viewModel.connectionStates[device.id] {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnecting:
            return .orange
        default:
            return .red
        }
    }
    
    private var connectionStateText: String {
        switch viewModel.connectionStates[device.id] {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .disconnecting:
            return "Disconnecting..."
        default:
            return "Disconnected"
        }
    }
}

struct ServiceView: View {
    let service: CBService
    @EnvironmentObject private var viewModel: BluetoothViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let serviceInfo = viewModel.getServiceInfo(service)
            
            HStack {
                Text(serviceInfo.name)
                    .font(.headline)
                Spacer()
                Text(service.uuid.uuidString)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Text(serviceInfo.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let characteristics = service.characteristics {
                Text("Characteristics (\(characteristics.count))")
                    .font(.subheadline)
                    .bold()
                    .padding(.top, 4)
                
                ForEach(characteristics, id: \.uuid) { characteristic in
                    CharacteristicView(characteristic: characteristic)
                        .padding(.leading)
                }
            } else {
                Text("Discovering characteristics...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            print("ServiceView appeared for service: \(service.uuid.uuidString)")
        }
    }
}

struct CharacteristicView: View {
    let characteristic: CBCharacteristic
    @EnvironmentObject private var viewModel: BluetoothViewModel
    @State private var showingWriteSheet = false
    @State private var writeValue: String = ""
    @State private var showingValueDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(viewModel.getCharacteristicName(characteristic))
                    .font(.subheadline)
                    .bold()
                Spacer()
                propertyIndicators
            }
            
            if characteristic.value != nil {
                Button(action: { showingValueDetails = true }) {
                    Text(viewModel.formatCharacteristicValue(characteristic))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            HStack(spacing: 12) {
                if viewModel.canReadCharacteristic(characteristic) {
                    Button(action: {
                        viewModel.readCharacteristic(characteristic)
                    }) {
                        Label("Read", systemImage: "doc.text")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
                
                if viewModel.canWriteCharacteristic(characteristic) {
                    Button(action: {
                        showingWriteSheet = true
                    }) {
                        Label("Write", systemImage: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
                
                if viewModel.canNotifyCharacteristic(characteristic) {
                    let isNotifying = viewModel.notifyingCharacteristics.contains(characteristic.uuid)
                    Button(action: {
                        viewModel.toggleNotifications(for: characteristic)
                    }) {
                        Label(isNotifying ? "Stop Notifications" : "Start Notifications",
                              systemImage: isNotifying ? "bell.fill" : "bell")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(isNotifying ? .orange : .gray)
                }
            }
        }
        .sheet(isPresented: $showingWriteSheet) {
            writeCharacteristicSheet
        }
        .sheet(isPresented: $showingValueDetails) {
            characteristicDetailsSheet
        }
    }
    
    private var propertyIndicators: some View {
        HStack(spacing: 4) {
            if characteristic.properties.contains(.read) {
                Image(systemName: "r.circle.fill")
                    .foregroundColor(.blue)
            }
            if characteristic.properties.contains(.write) {
                Image(systemName: "w.circle.fill")
                    .foregroundColor(.green)
            }
            if characteristic.properties.contains(.notify) {
                Image(systemName: "bell.circle.fill")
                    .foregroundColor(.orange)
            }
        }
        .font(.caption)
    }
    
    private var writeCharacteristicSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Write Value")) {
                    TextField("Hex Value (e.g., 01020304)", text: $writeValue)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                }
                
                Section(header: Text("Format")) {
                    Text("Enter value in hexadecimal format (e.g., 01 for 1%, FF for 100%)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button("Write") {
                        if let data = Data(hexString: writeValue) {
                            viewModel.writeCharacteristic(characteristic, data: data)
                            showingWriteSheet = false
                        }
                    }
                    .disabled(writeValue.isEmpty)
                }
            }
            .navigationTitle("Write to \(viewModel.getCharacteristicName(characteristic))")
            .navigationBarItems(trailing: Button("Cancel") {
                showingWriteSheet = false
            })
        }
    }
    
    private var characteristicDetailsSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Characteristic Information")) {
                    DetailRow(title: "Name", value: viewModel.getCharacteristicName(characteristic))
                    DetailRow(title: "UUID", value: characteristic.uuid.uuidString)
                    DetailRow(title: "Properties", value: propertiesDescription)
                }
                
                if let value = characteristic.value {
                    Section(header: Text("Value")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Formatted")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(viewModel.formatCharacteristicValue(characteristic))
                                .font(.system(.body, design: .monospaced))
                            
                            Divider()
                            
                            Text("Hexadecimal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(value.map { String(format: "%02X", $0) }.joined(separator: " "))
                                .font(.system(.body, design: .monospaced))
                            
                            if let ascii = String(data: value, encoding: .utf8) {
                                Divider()
                                
                                Text("ASCII")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(ascii)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Characteristic Details")
            .navigationBarItems(trailing: Button("Done") {
                showingValueDetails = false
            })
        }
    }
    
    private var propertiesDescription: String {
        var props: [String] = []
        let properties = characteristic.properties
        
        if properties.contains(.read) { props.append("Read") }
        if properties.contains(.write) { props.append("Write") }
        if properties.contains(.writeWithoutResponse) { props.append("Write Without Response") }
        if properties.contains(.notify) { props.append("Notify") }
        if properties.contains(.indicate) { props.append("Indicate") }
        if properties.contains(.authenticatedSignedWrites) { props.append("Signed Writes") }
        if properties.contains(.extendedProperties) { props.append("Extended Properties") }
        if properties.contains(.notifyEncryptionRequired) { props.append("Notify (Encrypted)") }
        if properties.contains(.indicateEncryptionRequired) { props.append("Indicate (Encrypted)") }
        
        return props.joined(separator: ", ")
    }
}

// Add Data extension for hex string conversion
extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            let bytes = hexString[index..<nextIndex]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            index = nextIndex
        }
        self = data
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

struct ConnectionSettingsView: View {
    let device: BluetoothDevice
    @EnvironmentObject private var viewModel: BluetoothViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings: BluetoothViewModel.ConnectionSettings
    @State private var showingAdvancedSettings = false
    @State private var mtuText: String
    @State private var timeoutText: String
    
    init(device: BluetoothDevice, initialSettings: BluetoothViewModel.ConnectionSettings? = nil) {
        self.device = device
        let settings = initialSettings ?? BluetoothViewModel.ConnectionSettings()
        _settings = State(initialValue: settings)
        _mtuText = State(initialValue: "\(settings.mtu)")
        _timeoutText = State(initialValue: String(format: "%.1f", settings.timeoutDuration))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Settings")) {
                    Toggle("Auto Reconnect", isOn: $settings.autoReconnect)
                    
                    Picker("Connection Priority", selection: $settings.connectionPriority) {
                        Text("High").tag(BluetoothViewModel.ConnectionSettings.ConnectionPriority.high)
                        Text("Balanced").tag(BluetoothViewModel.ConnectionSettings.ConnectionPriority.balanced)
                        Text("Low Power").tag(BluetoothViewModel.ConnectionSettings.ConnectionPriority.low)
                    }
                }
                
                Section(header: Text("Advanced Settings")) {
                    Toggle("Show Advanced Settings", isOn: $showingAdvancedSettings)
                    
                    if showingAdvancedSettings {
                        HStack {
                            Text("MTU Size")
                            Spacer()
                            TextField("MTU", text: $mtuText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                                .onChange(of: mtuText) { oldValue, newValue in
                                    if let mtu = Int(newValue) {
                                        settings.mtu = mtu
                                    }
                                }
                        }
                        
                        HStack {
                            Text("Connection Timeout")
                            Spacer()
                            TextField("Seconds", text: $timeoutText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .onChange(of: timeoutText) { oldValue, newValue in
                                    if let timeout = Double(newValue) {
                                        settings.timeoutDuration = timeout
                                    }
                                }
                        }
                    }
                }
                
                Section {
                    Button("Apply Settings") {
                        // Update final values from text fields
                        if let mtu = Int(mtuText) {
                            settings.mtu = mtu
                        }
                        if let timeout = Double(timeoutText) {
                            settings.timeoutDuration = timeout
                        }
                        viewModel.updateConnectionSettings(for: device.id, settings: settings)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Connection Settings")
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
        }
    }
}

struct ServicesSection: View {
    let device: BluetoothDevice
    @EnvironmentObject private var viewModel: BluetoothViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header
            HStack {
                Text("Available Services")
                    .font(.headline)
                if let services = device.services {
                    Text("(\(services.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 5)
            
            // Content
            Group {
                if let services = device.services {
                    if services.isEmpty {
                        EmptyServicesView()
                    } else {
                        ServicesList(services: services)
                    }
                } else {
                    LoadingServicesView(device: device, viewModel: viewModel)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(radius: 5)
        .animation(.default, value: device.services?.count ?? 0)
    }
}

struct EmptyServicesView: View {
    var body: some View {
        Text("No services found")
            .foregroundColor(.secondary)
    }
}

struct ServicesList: View {
    let services: [CBService]
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(services.enumerated()), id: \.element.uuid) { index, service in
                ServiceView(service: service)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .transition(.opacity)
                    .id(service.uuid)
            }
        }
    }
}

struct LoadingServicesView: View {
    let device: BluetoothDevice
    let viewModel: BluetoothViewModel
    
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .padding()
            Text("Discovering services...")
                .foregroundColor(.secondary)
            Text("Device ID: \(device.id)")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top, 5)
            
            // Debug information
            if let state = viewModel.connectionStates[device.id] {
                Text("Connection State: \(state.description)")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text("Connection State: unknown")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#Preview {
    BluetoothTrackerView()
}
