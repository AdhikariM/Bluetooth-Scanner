//
//  ContentView.swift
//  Bluetooth Tracker
//
//  Created by Mahesh Adhikari on 8/8/24.
//

import SwiftUI

struct BluetoothTrackerView: View {
    @StateObject private var viewModel = BluetoothViewModel()
    @State private var searchText = ""

    var filteredNames: [String] {
        if searchText.isEmpty {
            return viewModel.names
        } else {
            return viewModel.names.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var filteredIds: [NSNumber] {
        return filteredNames.compactMap { name in
            guard let index = viewModel.names.firstIndex(of: name) else { return nil }
            return viewModel.ids[index]
        }
    }

    var filteredCounts: [Int] {
        return filteredNames.compactMap { name in
            guard let index = viewModel.names.firstIndex(of: name) else { return nil }
            return viewModel.counts[index]
        }
    }

    var totalFilteredDevices: Int {
        return Set(filteredNames).count
    }

    var body: some View {
        NavigationStack {
            VStack {
                Text("Total Devices Found: \(totalFilteredDevices)")
                    .font(.headline)
                    .padding(.top)

                List {
                    ForEach(filteredNames.indices, id: \.self) { index in
                        HStack {
                            Text(filteredNames[index])
                            Spacer()
                            Text("RSSI: \(filteredIds[index])")
                                .foregroundColor(.gray)
                            Text("Seen: \(filteredCounts[index]) times")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .searchable(text: $searchText, prompt: Text("Search by name"))
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        viewModel.startScan()
                    }
                }
            }
            .onAppear {
                viewModel.startScan()
            }
        }
    }
}

#Preview {
    BluetoothTrackerView()
}
