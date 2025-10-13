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
    var locationManager: LocationManager? = nil
    @ObservedObject var dataManager: DataManager
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var description = ""
    @State private var selectedCategory: String = POICategory.scenic.rawValue
    
    @State private var isRefining = false
    @State private var refinedLocation: CLLocation? = nil
    
    // Choose the best available location to display/save: refined > freshest LM > injected
    private var bestCandidateLocation: CLLocation {
        let injected = location
        if let refined = refinedLocation { return refined }
        if let lm = locationManager?.location {
            // Prefer the newer and more accurate reading
            let newer = (lm.timestamp > injected.timestamp)
            let moreAccurate = (lm.horizontalAccuracy > 0 && lm.horizontalAccuracy < injected.horizontalAccuracy)
            if newer || moreAccurate { return lm }
        }
        return injected
    }
    
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
                            Text(String(format: "%.6f", bestCandidateLocation.coordinate.latitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Longitude:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.6f", bestCandidateLocation.coordinate.longitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Altitude:")
                                .fontWeight(.medium)
                            Spacer()
                            if bestCandidateLocation.verticalAccuracy < 0 {
                                Text("Unavailable")
                                    .foregroundColor(.secondary)
                            } else {
                                Text(String(format: "%.1f m", bestCandidateLocation.altitude))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Accuracy:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.1f m", bestCandidateLocation.horizontalAccuracy))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            if isRefining {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("Refining location…")
                                    .foregroundColor(.secondary)
                            } else {
                                Button("Refine for 2s") { startRefineWindow() }
                                    .font(.caption)
                            }
                            Spacer()
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
        let candidate = bestCandidateLocation
        // Optional: basic sanity check on staleness/accuracy (tunable)
        let isFresh = candidate.timestamp > Date().addingTimeInterval(-30)
        let hasReasonableAccuracy = candidate.horizontalAccuracy > 0 && candidate.horizontalAccuracy <= 50
        let locToUse = (isFresh && hasReasonableAccuracy) ? candidate : location
        
        let poi = PointOfInterest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            coordinate: POICoordinate(from: locToUse),
            timestamp: Date(),
            category: selectedCategory
        )
        
        dataManager.savePOI(poi)
        dismiss()
    }
    
    private func startRefineWindow() {
        guard !isRefining else { return }
        isRefining = true
        refinedLocation = nil
        let startTime = Date()
        
        // Poll the locationManager's latest fix a few times over ~2 seconds
        // This is simple and avoids additional delegate wiring for this small modal
        let interval: TimeInterval = 0.25
        let maxDuration: TimeInterval = 2.0
        func attempt() {
            // Grab the freshest LM reading if available
            if let lmLoc = locationManager?.location {
                if refinedLocation == nil {
                    refinedLocation = lmLoc
                } else if let current = refinedLocation {
                    let newer = lmLoc.timestamp > current.timestamp
                    let moreAccurate = lmLoc.horizontalAccuracy > 0 && current.horizontalAccuracy > 0 && lmLoc.horizontalAccuracy < current.horizontalAccuracy
                    if newer || moreAccurate { refinedLocation = lmLoc }
                }
            }
            if Date().timeIntervalSince(startTime) < maxDuration {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) { attempt() }
            } else {
                isRefining = false
            }
        }
        attempt()
    }
}

#Preview {
    AddPOIView(
        location: CLLocation(latitude: 37.7749, longitude: -122.4194),
        locationManager: nil,
        dataManager: DataManager()
    )
}
