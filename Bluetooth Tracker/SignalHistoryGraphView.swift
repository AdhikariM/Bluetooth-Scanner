//
//  SignalHistoryGraphView.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 3/31/25.
//


import SwiftUI
import Charts

struct SignalHistoryGraphView: View {
    let device: BluetoothDevice
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTimeRange: TimeRange = .fiveMinutes
    @State private var selectedDataPoint: (timestamp: Date, rssi: Int)?
    @State private var isZoomed = false
    
    enum TimeRange: String, CaseIterable {
        case oneMinute = "1 Min"
        case twoMinutes = "2 Mins"
        case fiveMinutes = "5 Mins"
        case fifteenMinutes = "15 Mins"
        
        var minutes: Int {
            switch self {
            case .oneMinute: return 1
            case .twoMinutes: return 2
            case .fiveMinutes: return 5
            case .fifteenMinutes: return 15
            }
        }
    }
    
    private var timeRange: ClosedRange<Date> {
        let startTime = Date().addingTimeInterval(-Double(selectedTimeRange.minutes * 60))
        return startTime...Date()
    }
    
    private var filteredHistory: [(timestamp: Date, rssi: Int)] {
        device.discoveryHistory.filter { timeRange.contains($0.timestamp) }
    }
    
    private var averageRSSI: Double {
        guard !filteredHistory.isEmpty else { return 0 }
        let sum = filteredHistory.reduce(0) { $0 + $1.rssi }
        return Double(sum) / Double(filteredHistory.count)
    }
    
    private var minRSSI: Int {
        filteredHistory.map { $0.rssi }.min() ?? 0
    }
    
    private var maxRSSI: Int {
        filteredHistory.map { $0.rssi }.max() ?? 0
    }
    
    private var chartContent: some View {
        Chart {
            ForEach(filteredHistory, id: \.timestamp) { data in
                LineMark(
                    x: .value("Time", data.timestamp),
                    y: .value("RSSI", data.rssi)
                )
                .foregroundStyle(signalColor(for: data.rssi))
                
                PointMark(
                    x: .value("Time", data.timestamp),
                    y: .value("RSSI", data.rssi)
                )
                .foregroundStyle(signalColor(for: data.rssi))
                .symbolSize(selectedDataPoint?.timestamp == data.timestamp ? 100 : 50)
                .annotation(position: .top) {
                    if selectedDataPoint?.timestamp == data.timestamp {
                        VStack {
                            Text("\(data.rssi) dBm")
                                .font(.caption)
                                .bold()
                            Text(formatDate(data.timestamp))
                                .font(.caption2)
                        }
                        .padding(4)
                        .background(Color(.systemBackground))
                        .cornerRadius(4)
                        .shadow(radius: 2)
                    }
                }
            }
        }
        .frame(height: isZoomed ? 300 : 200)
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel(formatDate(date))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                if let rssi = value.as(Int.self) {
                    AxisValueLabel("\(rssi) dBm")
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geometry[plotFrame]
                                let x = value.location.x - frame.origin.x
                                guard x >= 0, x <= frame.width else { return }
                                
                                let date = proxy.value(atX: x, as: Date.self) ?? Date()
                                if let closest = filteredHistory.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }) {
                                    selectedDataPoint = closest
                                }
                            }
                    )
            }
        }
    }
    
    private var statsCards: some View {
        HStack(spacing: 20) {
            StatCard(title: "Average", value: String(format: "%.1f dBm", averageRSSI))
            StatCard(title: "Min", value: "\(minRSSI) dBm")
            StatCard(title: "Max", value: "\(maxRSSI) dBm")
            StatCard(title: "Samples", value: "\(filteredHistory.count)")
        }
        .padding(.horizontal)
    }
    
    private var qualityLegend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signal Quality Guide")
                .font(.headline)
            
            HStack(spacing: 20) {
                QualityIndicator(color: .green, label: "Excellent")
                QualityIndicator(color: .blue, label: "Very Good")
                QualityIndicator(color: .yellow, label: "Good")
                QualityIndicator(color: .orange, label: "Fair")
                QualityIndicator(color: .red, label: "Poor")
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(radius: 5)
        .padding(.horizontal)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Time Range Selector
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    statsCards
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Signal Strength Over Time")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        chartContent
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(15)
                    .shadow(radius: 5)
                    .padding(.horizontal)
                    .onTapGesture {
                        withAnimation {
                            isZoomed.toggle()
                        }
                    }

                    qualityLegend
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Signal History")
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
    
    private func signalColor(for rssi: Int) -> Color {
        switch rssi {
        case ..<(-80): return .red
        case -80..<(-50): return .orange
        case -50..<(-30): return .yellow
        case -30..<(-20): return .blue
        default: return .green
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .bold()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 2)
    }
}

struct QualityIndicator: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
        }
    }
} 
