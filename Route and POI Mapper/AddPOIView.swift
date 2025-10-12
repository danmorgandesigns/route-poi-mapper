//
//  AddPOIView.swift
//  Route and POI Mapper
//
//  Created by Dan Morgan on 10/10/25.
//

import SwiftUI
import CoreLocation
import Combine

struct AddPOIView: View {
    let location: CLLocation
    @ObservedObject var dataManager: DataManager
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var description = ""
    @State private var selectedCategory: String = POICategory.scenic.rawValue
    
    var body: some View {
        NavigationView {
            Form {
                Section("Point of Interest Details") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.sentences)
                    
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(POICategory.allCases, id: \.self) { category in
                            Label(category.rawValue, systemImage: category.systemImage)
                                .tag(category.rawValue)
                        }
                    }
                }
                
                Section("Location") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Latitude:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.6f", location.coordinate.latitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Longitude:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.6f", location.coordinate.longitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Altitude:")
                                .fontWeight(.medium)
                            Spacer()
                            if location.verticalAccuracy < 0 {
                                Text("Unavailable")
                                    .foregroundColor(.secondary)
                            } else {
                                Text(String(format: "%.1f m", location.altitude))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Accuracy:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.1f m", location.horizontalAccuracy))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Add Point of Interest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        savePOI()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func savePOI() {
        let poi = PointOfInterest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            coordinate: POICoordinate(from: location),
            timestamp: Date(),
            category: selectedCategory
        )
        
        dataManager.savePOI(poi)
        dismiss()
    }
}

#Preview {
    AddPOIView(
        location: CLLocation(latitude: 37.7749, longitude: -122.4194),
        dataManager: DataManager()
    )
}
