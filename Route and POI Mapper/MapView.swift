//
//  MapView.swift
//  Route and POI Mapper
//
//  Created by Dan Morgan on 10/10/25.
//

import SwiftUI
import MapKit
import Combine
import UIKit
import CoreLocation

struct MapView: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var dataManager: DataManager
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco default
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    @State private var showingPOISheet = false
    @State private var selectedPOILocation: CLLocation?
    @State private var mapType: MKMapType = .satellite
    @State private var showingQuickPOIModal = false
    @State private var showingRouteModal = false
    @State private var showingFolderModal = false
    @State private var showingRouteNameModal = false
    @State private var didCenterInitially = false
    
    private var routePolylines: [MKPolyline] {
        var lines: [MKPolyline] = []
        // Finalized segments
        for segment in locationManager.currentSegments {
            let coords = segment.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
            if !coords.isEmpty {
                lines.append(MKPolyline(coordinates: coords, count: coords.count))
            }
        }
        // Active segment (if any) built from currentRoute tail since currentSegment isn't published
        // Fall back to building from the last N points in currentRoute to approximate the active segment
        // Note: For more precise rendering, consider publishing currentSegment in LocationManager
        if locationManager.isTracking && !locationManager.isPaused {
            // Try to infer the active segment by taking recent points since last pause
            // As a simple approach, draw the entire currentRoute as the active line if no segments exist yet
            let coords = locationManager.currentRoute.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            if coords.count > 1 {
                lines.append(MKPolyline(coordinates: coords, count: coords.count))
            }
        }
        return lines
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                UIKitMapView(region: $region, polylines: routePolylines, poiAnnotations: poiAnnotations)
                    .ignoresSafeArea(.all)
                    .onReceive(locationManager.$location) { location in
                        if let location = location, !didCenterInitially {
                            didCenterInitially = true
                            withAnimation { region.center = location.coordinate }
                        }
                    }
                    .onReceive(dataManager.$savedPOIs) { poIs in
                        guard let latest = poIs.last else { return }
                        region.center = latest.coordinate.clLocationCoordinate2D
                    }
                
                // Route info overlay with subtle material effect
                VStack {
                    Spacer()
                    
                    if locationManager.isTracking {
                        RouteInfoOverlay(locationManager: locationManager)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .bottomBar)
            .toolbarColorScheme(.dark, for: .bottomBar) // Force transparent bottom toolbar
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        mapType = mapType == .satellite ? .standard : .satellite
                    }) {
                        Image(systemName: mapType == .satellite ? "globe" : "map")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if let location = locationManager.location {
                            withAnimation {
                                region.center = location.coordinate
                            }
                        }
                    }) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                // Bottom toolbar items 
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button(action: {
                            showingRouteModal = true
                        }) {
                            Image(systemName: "figure.hiking")
                        }
                        .padding(.leading, 20)  // Push hiking button right
                        
                        Spacer()
                        
                        Button(action: {
                            print("Button tapped!")
                            if let currentLocation = locationManager.location {
                                print("Location available: \(currentLocation)")
                                selectedPOILocation = currentLocation
                                // Use a small delay to ensure state is updated before presenting
                                DispatchQueue.main.async {
                                    showingQuickPOIModal = true
                                }
                            } else {
                                print("No location available")
                                // For debugging, create a dummy location
                                let dummyLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
                                selectedPOILocation = dummyLocation
                                DispatchQueue.main.async {
                                    showingQuickPOIModal = true
                                }
                            }
                        }) {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            showingFolderModal = true
                        }) {
                            Image(systemName: "folder")
                        }
                        .padding(.trailing, 20)  // Push folder button left
                    }
                }
            }
        }
        .sheet(isPresented: $showingPOISheet) {
            if let location = selectedPOILocation {
                AddPOIView(location: location, dataManager: dataManager)
            }
        }
        .sheet(isPresented: $showingQuickPOIModal) {
            QuickPOIModal(
                location: selectedPOILocation,
                locationManager: locationManager,
                dataManager: dataManager
            )
        }
        .sheet(isPresented: $showingRouteModal) {
            RouteConfirmationModal(locationManager: locationManager, showingRouteNameModal: $showingRouteNameModal)
        }
        .sheet(isPresented: $showingRouteNameModal) {
            RouteNamingModal { name in
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackName: String = {
                    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                    return "Route-\(df.string(from: Date()))"
                }()
                let finalName = trimmedName.isEmpty ? fallbackName : trimmedName

                // Build and persist the route model first (now includes segments)
                if let route = locationManager.createTrailRoute(name: finalName) {
                    dataManager.saveRoute(route)

                    // Build segments array for metrics
                    let segments: [[[Double]]]
                    if let segs = route.segments { segments = segs } else {
                        let single = route.coordinates.map { [ $0.longitude, $0.latitude, $0.altitude ] }
                        segments = single.isEmpty ? [] : [single]
                    }

                    // Compute distance (miles) and elevation gain (feet)
                    func computeDistanceMilesAndElevationFeet(from segments: [[[Double]]]) -> (Double, Double) {
                        var totalMeters: Double = 0
                        var totalAscentMeters: Double = 0
                        for seg in segments {
                            guard seg.count > 1 else { continue }
                            for i in 1..<seg.count {
                                let prev = seg[i - 1]
                                let curr = seg[i]
                                let p1 = CLLocation(latitude: prev[1], longitude: prev[0])
                                let p2 = CLLocation(latitude: curr[1], longitude: curr[0])
                                totalMeters += p1.distance(from: p2)
                                if prev.count > 2 && curr.count > 2 {
                                    let delta = curr[2] - prev[2]
                                    if delta > 0 { totalAscentMeters += delta }
                                }
                            }
                        }
                        let miles = totalMeters / 1609.344
                        let feet = totalAscentMeters * 3.28084
                        return (miles, feet)
                    }

                    let (miles, feet) = computeDistanceMilesAndElevationFeet(from: segments)
                    let infoString = String(format: "Length: %.2f miles. Elevation %.0f feet.", miles, feet)

                    // Use the centralized export shape from the model
                    let collection = route.exportGeoJSON(info: infoString)
                    do {
                        let data = try JSONSerialization.data(withJSONObject: collection, options: .prettyPrinted)
                        if data.isEmpty {
                            print("[Route Export] exportGeoJSON produced empty data for route: \(finalName)")
                        } else {
                            if let url = dataManager.saveGeoJSONRouteFile(named: finalName, data: data) {
                                print("[Route Export] Wrote .geojson file: \(url.lastPathComponent)")
                            } else {
                                print("[Route Export] Failed to write .geojson file for route: \(finalName)")
                            }
                        }
                    } catch {
                        print("[Route Export] Failed to serialize exportGeoJSON: \(error)")
                    }
                } else {
                    print("[Route Export] Failed to create TrailRoute for name: \(finalName)")
                }
            }
        }
        .sheet(isPresented: $showingFolderModal) {
            SavedDataView(dataManager: dataManager)
        }
    }
    
    private var poiAnnotations: [PointOfInterest] {
        dataManager.savedPOIs
    }
}

struct UIKitMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var polylines: [MKPolyline]
    var poiAnnotations: [PointOfInterest]
    
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.mapType = .satellite
        map.region = region
        return map
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.setRegion(region, animated: false)
        // Update overlays
        uiView.removeOverlays(uiView.overlays)
        uiView.addOverlays(polylines)
        // Update POI annotations
        uiView.removeAnnotations(uiView.annotations.filter { !($0 is MKUserLocation) })
        let annotations = poiAnnotations.map { poi -> MKPointAnnotation in
            let ann = MKPointAnnotation()
            ann.title = poi.name
            ann.coordinate = poi.coordinate.clLocationCoordinate2D
            return ann
        }
        uiView.addAnnotations(annotations)
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: UIKitMapView
        init(_ parent: UIKitMapView) { self.parent = parent }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemRed
                renderer.lineWidth = 4
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

struct RouteInfoOverlay: View {
    @ObservedObject var locationManager: LocationManager
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "figure.hiking")
                    .foregroundColor(.green)
                
                Text("Tracking Route")
                    .font(.headline)
                    .foregroundColor(.green)
                
                Spacer()
                
                Text("\(locationManager.currentRoute.count) points")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let startTime = locationManager.routeStartTime {
                HStack {
                    Text("Duration: \(formatDuration(from: startTime))")
                        .font(.subheadline)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.9))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private func formatDuration(from startTime: Date) -> String {
        let duration = Date().timeIntervalSince(startTime)
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        
        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes)
        } else {
            return String(format: "%d min", minutes)
        }
    }
}

struct POIAnnotationView: View {
    let poi: PointOfInterest
    @State private var showingDetails = false
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(.blue)
                .clipShape(Circle())
                .onTapGesture {
                    showingDetails = true
                }
            
            Text(poi.name)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .sheet(isPresented: $showingDetails) {
            POIDetailsView(poi: poi)
        }
    }
}

struct POIDetailsView: View {
    let poi: PointOfInterest
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading) {
                        Text(poi.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(poi.category)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                if !poi.description.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.headline)
                        
                        Text(poi.description)
                            .font(.body)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location Details")
                        .font(.headline)
                    
                    Group {
                        HStack {
                            Text("Latitude:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.6f", poi.coordinate.latitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Longitude:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.6f", poi.coordinate.longitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Altitude:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.1f m", poi.coordinate.altitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Recorded:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(poi.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Point of Interest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct QuickPOIModal: View {
    let location: CLLocation?
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var poiName: String = ""
    @State private var selectedCategory = ""
    @State private var showingCategoryCustomization = false
    
    private var effectiveLocation: CLLocation? {
        location ?? locationManager.location
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Point of Interest Details") {
                    TextField("Name", text: $poiName)
                        .textInputAutocapitalization(.words)
                    
                    Picker("Category", selection: $selectedCategory) {
                        Text("Select Category").tag("")
                        ForEach(dataManager.customCategories.sorted().map { String(describing: $0) }, id: \.self) { categoryName in
                            Text(categoryName).tag(categoryName)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section("Location") {
                    if let loc = effectiveLocation {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Latitude:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(String(format: "%.6f", loc.coordinate.latitude))
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Longitude:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(String(format: "%.6f", loc.coordinate.longitude))
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Altitude:")
                                    .fontWeight(.medium)
                                Spacer()
                                if loc.verticalAccuracy < 0 {
                                    Text("Unavailable")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(String(format: "%.1f m", loc.altitude))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } else {
                        HStack {
                            ProgressView()
                            Text("Acquiring location…")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Button("Customize categories") {
                            showingCategoryCustomization = true
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Add Quick POI")
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
                    .disabled(poiName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCategory.isEmpty || effectiveLocation == nil)
                }
            }
        }
        .sheet(isPresented: $showingCategoryCustomization) {
            CategoryCustomizationView(dataManager: dataManager)
        }
    }
    
    private func savePOI() {
        guard let loc = effectiveLocation else { return }
        let poi = PointOfInterest(
            name: poiName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: "",
            coordinate: POICoordinate(from: loc),
            timestamp: Date(),
            category: selectedCategory
        )
        
        dataManager.savePOI(poi)
        dismiss()
    }
}

// MARK: - Route Confirmation Modal
struct RouteConfirmationModal: View {
    @ObservedObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @Binding var showingRouteNameModal: Bool

    private var titleText: String { locationManager.isTracking ? "Route Tracking" : "Start Route Tracking" }
    private var headlineText: String { locationManager.isTracking ? "Route Tracking Active" : "Start Route Tracking" }
    private var bodyText: String {
        if locationManager.isTracking {
            return "Your route is currently being tracked. You can stop tracking at any time."
        } else {
            return "This will begin tracking your hiking route. Your location will be recorded until you stop tracking."
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "figure.hiking")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top)
                
                Text(headlineText)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(bodyText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                VStack(spacing: 12) {
                    if locationManager.isTracking {
                        Button(action: {
                            locationManager.stopRouteTracking()
                            showingRouteNameModal = true
                            dismiss()
                        }) {
                            Text("Stop Route Tracking")
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        Button(action: {
                            if locationManager.isPaused {
                                locationManager.resumeRouteTracking()
                            } else {
                                locationManager.pauseRouteTracking()
                            }
                        }) {
                            Text(locationManager.isPaused ? "Resume" : "Pause")
                                .foregroundColor(locationManager.isPaused ? .white : .blue)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .background(locationManager.isPaused ? Color.blue : Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Button(action: {
                            locationManager.startRouteTracking()
                            dismiss()
                        }) {
                            Text("Start Tracking")
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

struct RouteNamingModal: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    let onSave: (String) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Route Name") {
                    TextField("Enter a name", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Save Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    MapView(
        locationManager: LocationManager(),
        dataManager: DataManager()
    )
}

